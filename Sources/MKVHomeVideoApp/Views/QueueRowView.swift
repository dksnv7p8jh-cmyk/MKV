import SwiftUI
import MKVHomeVideoCore

struct QueueRowView: View {
    let job: ConversionJob
    let preview: () -> Void
    let editMetadata: () -> Void
    let reveal: () -> Void
    let retry: () -> Void
    let skip: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: job.profile == .movie ? "film" : "tv")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle).fontWeight(.medium)
                Text(job.sourceURL.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                if let error = job.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(statusText).font(.caption).foregroundStyle(statusColor)
                if job.status == .running {
                    ProgressView(value: job.progress).frame(width: 115)
                }
            }
            Menu {
                Button("Preview", action: preview)
                Button("Edit Metadata…", action: editMetadata)
                if job.status == .completed { Button(job.operation == .metadataEdit ? "Reveal File" : "Reveal Output", action: reveal) }
                if job.status == .failed || job.status == .skipped || job.status == .paused { Button("Retry", action: retry) }
                if job.status == .queued || job.status == .failed { Button("Skip", action: skip) }
                if job.status != .running {
                    Divider()
                    Button("Remove", role: .destructive, action: remove)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 4)
    }

    private var displayTitle: String {
        let metadata = job.resolvedMetadata
        return metadata.title ?? metadata.episodeTitle ?? job.destinationURL.deletingPathExtension().lastPathComponent
    }

    private var statusText: String {
        switch job.status {
        case .queued: "Queued"
        case .running: job.operation == .metadataEdit ? "Updating metadata \(Int(job.progress * 100))%" : "Converting \(Int(job.progress * 100))%"
        case .paused: "Paused"
        case .completed: job.operation == .metadataEdit ? "Metadata updated" : "Complete"
        case .failed: "Failed"
        case .skipped: "Skipped"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .completed: .green
        case .failed: .red
        case .running: .accentColor
        default: .secondary
        }
    }
}
