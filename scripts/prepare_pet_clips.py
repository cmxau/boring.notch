"""Prepares the closed-notch pet clips in boringNotch/pets from the original cat GIFs.

Crops every clip to one shared canvas (so the cat stays the same size between clips, standing on the same
floor), shrinks it for the notch and saves it as a GIF.

usage: python3 scripts/prepare_pet_clips.py <folder with the original GIFs> boringNotch/pets
Needs Pillow.
"""
import sys, os
from PIL import Image, ImageSequence
src, out = sys.argv[1], sys.argv[2]
clips = {
    'PetResting': 'orange_cat_resting.gif',
    'PetWalking': 'orange_cat_walking.gif',
    'PetPlayingWithTail': 'orange_cat_playing_with_tail.gif',
    'PetPlayingWithBall': 'orange_cat_playing_with_tennis_ball.gif',
}
REF_W = 512  # most clips draw the cat at the same size relative to the frame width
# The tennis ball clip draws a smaller cat; it also has a stray strip of another sprite along its top
EXTRA_SCALE = {'PetPlayingWithBall': 1.3}
BLANK_ABOVE = {'PetPlayingWithBall': 104}
OUT_H = 84   # canvas height in pixels (about 3x the pet's height in points)
data = {}
for name, f in clips.items():
    im = Image.open(os.path.join(src, f))
    s = REF_W / im.size[0] * EXTRA_SCALE.get(name, 1)
    frames, durs = [], []
    for fr in ImageSequence.Iterator(im):
        rgb = fr.convert('RGB')
        if name in BLANK_ABOVE:
            rgb.paste((0, 0, 0), (0, 0, rgb.size[0], BLANK_ABOVE[name]))
        frames.append(rgb.resize((round(rgb.size[0]*s), round(rgb.size[1]*s)), Image.LANCZOS))
        durs.append(fr.info.get('duration', 100))
    boxes = [f.convert('L').point(lambda v: 255 if v > 24 else 0).getbbox() for f in frames]
    u = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    data[name] = (frames, durs, u)
W = max(u[2]-u[0] for _, _, u in data.values())
H = max(u[3]-u[1] for _, _, u in data.values())
scale = OUT_H / H
ow = round(W * scale)
print('canvas', W, H, '->', ow, OUT_H)
os.makedirs(out, exist_ok=True)
for name, (frames, durs, u) in data.items():
    cw, ch = u[2]-u[0], u[3]-u[1]
    res = []
    for f in frames:
        c = Image.new('RGB', (W, H))
        # bottom-aligned, horizontally centred
        c.paste(f.crop(u), ((W-cw)//2, H-ch))
        res.append(c.resize((ow, OUT_H), Image.LANCZOS).quantize(colors=128, method=Image.MEDIANCUT, dither=Image.NONE))
    p = os.path.join(out, name + '.gif')
    res[0].save(p, save_all=True, append_images=res[1:], duration=durs, loop=0, disposal=1, optimize=False)
    print(name, len(res), 'frames', os.path.getsize(p), 'bytes')
