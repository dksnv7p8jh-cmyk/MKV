import SwiftUI
import UniformTypeIdentifiers
import MKVHomeVideoCore

struct SetupView: View {
    let model: AppViewModel

    var body: some View {
        ContentUnavailableView {
            Label("FFmpeg setup needed", systemImage: "wrench.and.screwdriver")
        } description: {
            Text("MKV Home Video uses a locally installed FFmpeg and ffprobe pair. Your video files stay on this Mac.")
        } actions: {
            VStack(spacing: 12) {
                Text(model.setupCommand)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                HStack {
                    Button("Choose FFmpeg…", action: chooseFFmpeg)
                    Button("Check Again") { model.refreshToolchain() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func chooseFFmpeg() {
        guard let url = NativeOpenPanel.chooseFiles(
            contentTypes: [.unixExecutable, .data],
            allowsMultipleSelection: false,
            message: "Choose the ffmpeg executable. Its ffprobe sibling is required.",
            prompt: "Choose FFmpeg"
        )?.first else { return }
        model.setCustomFFmpegURL(url)
    }
}
