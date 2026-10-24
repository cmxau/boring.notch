//
//  AboutDocuments.swift
//  boringNotch
//
//  The readable documents behind Settings > About: release notes (from this fork's GitHub releases), the privacy
//  policy and the terms of use.
//

import SwiftUI

enum AboutDocument: String, Identifiable {
    case releaseNotes = "Release Notes"
    case privacyPolicy = "Privacy Policy"
    case termsOfUse = "Terms of Use"

    var id: String { rawValue }
}

struct AboutDocumentSheet: View {
    let document: AboutDocument
    @Environment(\.dismiss) private var dismiss
    @State private var releaseNotes: String?
    @State private var releaseNotesFailed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(document.rawValue)
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                Group {
                    switch document {
                    case .releaseNotes:
                        if let releaseNotes {
                            markdown(releaseNotes)
                        } else if releaseNotesFailed {
                            Text("Release notes couldn't be loaded. They're also on GitHub.")
                                .foregroundStyle(.secondary)
                            Link("Open releases on GitHub", destination: AppLinks.releases)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        }
                    case .privacyPolicy:
                        markdown(LegalText.privacyPolicy)
                    case .termsOfUse:
                        markdown(LegalText.termsOfUse)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .frame(width: 520, height: 520)
        .task {
            guard document == .releaseNotes else { return }
            if let notes = await ReleaseNotesLoader.load() {
                releaseNotes = notes
            } else {
                releaseNotesFailed = true
            }
        }
    }

    /// Renders paragraphs and headings; Markdown inline styling (bold, links) inside each line.
    private func markdown(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("## ") {
                    Text(inline(String(trimmed.dropFirst(3)))).font(.title3).fontWeight(.semibold).padding(.top, 6)
                } else if trimmed.hasPrefix("# ") {
                    Text(inline(String(trimmed.dropFirst(2)))).font(.title2).fontWeight(.bold)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(inline(String(trimmed.dropFirst(2))))
                    }
                } else if !trimmed.isEmpty {
                    Text(inline(trimmed))
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// The latest few releases of this fork, newest first, as Markdown.
enum ReleaseNotesLoader {
    private struct Release: Decodable {
        let name: String?
        let tag_name: String
        let body: String?
        let draft: Bool
    }

    static func load() async -> String? {
        var request = URLRequest(url: AppLinks.releasesAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let releases = try? JSONDecoder().decode([Release].self, from: data)
        else { return nil }
        let published = releases.filter { !$0.draft }.prefix(5)
        guard !published.isEmpty else { return "No releases yet." }
        return published.map { release in
            "## \(release.name ?? release.tag_name)\n\(release.body ?? "")"
        }.joined(separator: "\n\n")
    }
}

enum LegalText {
    static let privacyPolicy = """
    # Privacy Policy

    Boring Notch runs on your Mac. It has no account, no analytics and no tracking, and it doesn't send your data to us.

    ## What stays on your Mac
    - Settings, shelf items and clipboard history are stored only on this Mac.
    - Calendar events and reminders are read on this Mac to show them in the notch.
    - The camera is only used for the mirror while you have it open; nothing is recorded.
    - System audio is analysed live to drive the equaliser; nothing is recorded or kept.
    - AI agents report to the notch over a connection that never leaves this Mac (or your own SSH tunnel).

    ## What goes over the internet
    - **Lyrics:** the title and artist of the song playing are sent to a public lyrics service to find its lyrics.
    - **Updates and release notes:** Boring Notch checks GitHub for new versions and release notes.
    - **Music apps:** controlling Spotify, Apple Music and other players happens on this Mac.

    ## Contact
    Questions about privacy can be raised as an issue on the project's GitHub page.
    """

    static let termsOfUse = """
    # Terms of Use

    Boring Notch is free, open-source software, provided **as is**, without warranty of any kind.

    ## Using Boring Notch
    - You can use, copy and modify it under the terms of its open-source licence (GPL-3.0), included with the source code.
    - Alpha and beta builds can contain bugs; keep backups of anything important.
    - Some features control other apps (music players, terminals, AI agents) on your behalf. You're responsible for what you approve.

    ## Liability
    The authors aren't liable for any damage or loss arising from using Boring Notch.

    ## Trademarks
    App names and icons shown in Boring Notch belong to their owners and are shown only to identify them.
    """
}
