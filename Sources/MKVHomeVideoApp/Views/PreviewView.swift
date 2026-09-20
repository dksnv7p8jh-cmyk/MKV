import AVFoundation
import AVKit
import SwiftUI

struct PreviewView: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var nativePlaybackUnavailable = false

    var body: some View {
        Group {
            if nativePlaybackUnavailable {
                ContentUnavailableView(
                    "Native preview unavailable",
                    systemImage: "play.slash",
                    description: Text("This MKV cannot be previewed natively. Convert it to make a compatible MP4.")
                )
            } else if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView("Preparing preview…")
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .task(id: url) {
            let asset = AVURLAsset(url: url)
            let playable = (try? await asset.load(.isPlayable)) ?? false
            nativePlaybackUnavailable = !playable
            guard playable else { return }
            let newPlayer = AVPlayer(url: url)
            player = newPlayer
            newPlayer.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
