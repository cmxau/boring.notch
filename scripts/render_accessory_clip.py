"""Render a looping turntable clip of a 3D model for the accessory-connected indicator.

The clip matches the bundled AirPods clips in boringNotch/accessories: 96x96 pixels, 60 fps, 6 seconds,
one full turn around the vertical axis, on a pure black background so it blends into the notch.

Usage, with Blender installed:
    blender -b -P scripts/render_accessory_clip.py -- model.glb boringNotch/accessories/ps5-controller.mp4

or with the bpy module (pip install bpy):
    python scripts/render_accessory_clip.py model.glb boringNotch/accessories/ps5-controller.mp4

Supported model formats: .glb, .gltf, .fbx, .obj, .usd/.usdz, .blend. ffmpeg must be on the PATH.
"""

import argparse
import math
import os
import shutil
import subprocess
import sys
import tempfile

import bpy
from mathutils import Euler, Matrix, Vector


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("model", help="3D model to render")
    parser.add_argument("output", help="Where to write the .mp4")
    parser.add_argument("--size", type=int, default=96, help="Output size in pixels (default 96)")
    parser.add_argument("--supersample", type=int, default=4, help="Render at this multiple of --size, then downscale")
    parser.add_argument("--fps", type=int, default=60)
    parser.add_argument("--seconds", type=float, default=6)
    parser.add_argument("--samples", type=int, default=48, help="Cycles samples per frame")
    parser.add_argument("--fill", type=float, default=0.92, help="Share of the frame the model's widest extent fills")
    parser.add_argument("--elevation", type=float, default=22, help="Camera angle above the horizon, in degrees")
    parser.add_argument("--pitch", type=float, default=0, help="Tilt the model towards the camera, in degrees")
    parser.add_argument("--roll", type=float, default=0, help="Roll the model, in degrees")
    parser.add_argument("--yaw", type=float, default=0, help="Starting turn of the model, in degrees")
    parser.add_argument("--frames-dir", help="Keep the rendered frames here instead of a temporary folder")
    return parser.parse_args(argv)


def import_model(path):
    ext = os.path.splitext(path)[1].lower()
    before = set(bpy.data.objects)
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext in (".usd", ".usda", ".usdc", ".usdz"):
        bpy.ops.wm.usd_import(filepath=path)
    elif ext == ".blend":
        with bpy.data.libraries.load(path) as (data_from, data_to):
            data_to.objects = data_from.objects
        for obj in data_to.objects:
            if obj is not None:
                bpy.context.scene.collection.objects.link(obj)
    else:
        sys.exit(f"Unsupported model format: {ext}")

    imported = [obj for obj in bpy.data.objects if obj not in before]
    # Scene files often bring their own cameras, lights and backdrops; keep only the model
    for obj in imported:
        if obj.type in {"CAMERA", "LIGHT"}:
            bpy.data.objects.remove(obj, do_unlink=True)
    return [obj for obj in bpy.data.objects if obj not in before]


def world_bounds(objects):
    points = []
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in objects:
        if obj.type != "MESH":
            continue
        evaluated = obj.evaluated_get(depsgraph)
        points.extend(evaluated.matrix_world @ Vector(corner) for corner in evaluated.bound_box)
    if not points:
        sys.exit("The model has no meshes")
    low = Vector(min(p[i] for p in points) for i in range(3))
    high = Vector(max(p[i] for p in points) for i in range(3))
    return low, high, points


def build_turntable(objects, args):
    # Pivot that the model is parented to, so it can be re-oriented, centred and spun as one piece
    pivot = bpy.data.objects.new("Turntable", None)
    bpy.context.scene.collection.objects.link(pivot)
    roots = [obj for obj in objects if obj.parent is None or obj.parent not in objects]
    for obj in roots:
        world = obj.matrix_world.copy()
        obj.parent = pivot
        obj.matrix_world = world

    orientation = Euler((math.radians(args.pitch), math.radians(args.roll), math.radians(args.yaw)), "XYZ")
    pivot.matrix_world = orientation.to_matrix().to_4x4()
    bpy.context.view_layer.update()

    # Centre on the model and scale it so its turning circle has a radius of 1
    low, high, points = world_bounds(objects)
    center = (low + high) / 2
    radius_xy = max(math.hypot(p.x - center.x, p.y - center.y) for p in points)
    half_height = (high.z - low.z) / 2
    scale = 1 / max(radius_xy, half_height, 1e-6)

    turntable = bpy.data.objects.new("Spin", None)
    bpy.context.scene.collection.objects.link(turntable)
    pivot.parent = turntable
    pivot.matrix_world = (
        Matrix.Scale(scale, 4) @ Matrix.Translation(-center) @ orientation.to_matrix().to_4x4()
    )

    frame_count = round(args.fps * args.seconds)
    turntable.rotation_euler = (0, 0, 0)
    turntable.keyframe_insert("rotation_euler", index=2, frame=0)
    turntable.rotation_euler = (0, 0, 2 * math.pi)
    turntable.keyframe_insert("rotation_euler", index=2, frame=frame_count)
    set_linear(turntable)
    return frame_count, half_height * scale


def set_linear(obj):
    action = obj.animation_data.action
    curves = getattr(action, "fcurves", None)
    if curves is None:
        # Blender 5 keeps curves in layered actions
        curves = [c for layer in action.layers for strip in layer.strips for bag in strip.channelbags for c in bag.fcurves]
    for curve in curves:
        for key in curve.keyframe_points:
            key.interpolation = "LINEAR"


def add_camera(args, half_height):
    camera_data = bpy.data.cameras.new("Camera")
    camera_data.lens = 85
    camera_data.sensor_width = 36
    camera = bpy.data.objects.new("Camera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    bpy.context.scene.camera = camera

    # Far enough that the turning circle (radius 1) fills `fill` of the frame from any angle
    elevation = math.radians(args.elevation)
    extent = max(1.0, half_height) / args.fill
    half_fov = math.atan(camera_data.sensor_width / 2 / camera_data.lens)
    distance = extent / math.tan(half_fov) + 1
    camera.location = (0, -distance * math.cos(elevation), distance * math.sin(elevation))
    camera.rotation_euler = (math.pi / 2 - elevation, 0, 0)
    camera_data.clip_start = 0.01
    camera_data.clip_end = distance * 4


def add_lighting():
    scene = bpy.context.scene

    # The camera sees pure black; reflections and bounce light see a soft studio gradient
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    nodes = world.node_tree.nodes
    links = world.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputWorld")
    mix = nodes.new("ShaderNodeMixShader")
    light_path = nodes.new("ShaderNodeLightPath")
    black = nodes.new("ShaderNodeBackground")
    black.inputs["Color"].default_value = (0, 0, 0, 1)
    studio = nodes.new("ShaderNodeBackground")
    studio.inputs["Strength"].default_value = 0.35
    gradient = nodes.new("ShaderNodeTexGradient")
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.02, 0.02, 0.02, 1)
    ramp.color_ramp.elements[1].color = (0.9, 0.9, 0.9, 1)
    coords = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    # Gradient from the floor (dark) to overhead (bright)
    mapping.inputs["Rotation"].default_value = (0, -math.pi / 2, 0)
    links.new(coords.outputs["Generated"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], gradient.inputs["Vector"])
    links.new(gradient.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], studio.inputs["Color"])
    links.new(light_path.outputs["Is Camera Ray"], mix.inputs["Fac"])
    links.new(studio.outputs["Background"], mix.inputs[1])
    links.new(black.outputs["Background"], mix.inputs[2])
    links.new(mix.outputs["Shader"], output.inputs["Surface"])

    def area_light(name, location, energy, size):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.size = size
        light = bpy.data.objects.new(name, data)
        scene.collection.objects.link(light)
        light.location = location
        direction = -Vector(location)
        light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    # Key light from the front left, a softer fill from the right, and a rim from behind
    area_light("Key", (-3, -4, 4), 450, 3)
    area_light("Fill", (4, -3, 1.5), 90, 4)
    area_light("Rim", (0, 5, 3), 320, 3)


def configure_render(args, frame_count, frames_dir):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = args.samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = args.size * args.supersample
    scene.render.resolution_y = args.size * args.supersample
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    # AgX rolls highlights off gently (white plastic keeps its shading) and keeps black at zero
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "None"
    scene.render.fps = args.fps
    scene.frame_start = 0
    # The last keyframe equals the first, so stop one frame short for a seamless loop
    scene.frame_end = frame_count - 1
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.filepath = os.path.join(frames_dir, "frame_")


def encode(args, frames_dir):
    if shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg is needed to encode the clip")
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    subprocess.run(
        [
            "ffmpeg", "-v", "error", "-y",
            "-framerate", str(args.fps),
            "-start_number", "0",
            "-i", os.path.join(frames_dir, "frame_%04d.png"),
            "-vf", f"scale={args.size}:{args.size}:flags=lanczos",
            "-c:v", "libx264", "-preset", "slow", "-crf", "16",
            "-pix_fmt", "yuv420p",
            "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "iec61966-2-1", "-color_range", "tv",
            "-movflags", "+faststart",
            "-an",
            args.output,
        ],
        check=True,
    )


def main():
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)

    objects = import_model(os.path.abspath(args.model))
    frame_count, half_height = build_turntable(objects, args)
    add_camera(args, half_height)
    add_lighting()

    frames_dir = args.frames_dir or tempfile.mkdtemp(prefix="accessory-clip-")
    os.makedirs(frames_dir, exist_ok=True)
    configure_render(args, frame_count, frames_dir)
    bpy.ops.render.render(animation=True)
    encode(args, frames_dir)
    if not args.frames_dir:
        shutil.rmtree(frames_dir, ignore_errors=True)
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
