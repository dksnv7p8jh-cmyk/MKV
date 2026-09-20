import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MKVHomeVideoCore

private struct PreviewTarget: Identifiable {
    let id = UUID()
    let url: URL
}

struct QueueView: View {
    let model: AppViewModel
    @State private var selectedIDs = Set<UUID>()
    @State private var editingJob: ConversionJob?
    @State private var previewTarget: PreviewTarget?
    @State private var isEditingSharedMetadata = false
    @State private var errorMessage: String?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.jobs.isEmpty {
                dropArea
            } else {
                queueList
            }
            Divider()
            footer
        }
        .background(isDropTargeted ? Color.accentColor.opacity(0.08) : .clear)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: acceptDrop)
        .sheet(item: $editingJob) { job in
            MetadataEditorView(job: job) { profile, patch in
                model.updateJobMetadata(id: job.id, profile: profile, metadataOverride: patch)
            }
        }
        .sheet(isPresented: $isEditingSharedMetadata) {
            SharedMetadataEditorView(
                initialMetadata: sharedMetadataSeed,
                initialProfile: sharedMetadataProfile
            ) { profile, patch in
                model.setSharedMetadata(patch, profile: profile, for: selectedIDs)
            }
        }
        .sheet(item: $previewTarget) { target in
            PreviewView(url: target.url)
        }
        .alert("MKV Home Video needs attention", isPresented: Binding(
            get: { activeErrorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                    model.controller.clearPersistenceError()
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(activeErrorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("MKV Home Video", systemImage: "film.stack")
                .font(.title2.weight(.semibold))
            Spacer()
            Button("Add Files…", action: chooseFiles)
            Button("Add Folder…", action: chooseFolder)
            Button("Destination…", action: chooseDestination)
        }
        .padding()
        .disabled(model.controller.isExecuting)
    }

    private var dropArea: some View {
        ContentUnavailableView {
            Label("Drop MKVs here", systemImage: "arrow.down.doc")
        } description: {
            Text("Add files or folders to create a batch. Source MKVs are never modified.")
        } actions: {
            Button("Choose MKV Files…", action: chooseFiles)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var queueList: some View {
        List(selection: $selectedIDs) {
            ForEach(model.jobs) { job in
                QueueRowView(
                    job: job,
                    preview: { preview(job) },
                    editMetadata: { editingJob = job },
                    reveal: { NSWorkspace.shared.activateFileViewerSelecting([job.destinationURL]) },
                    retry: { model.controller.retry(job.id) },
                    skip: { model.controller.skip(job.id) },
                    remove: { model.controller.remove(job.id) }
                )
                .tag(job.id)
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(destinationDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !model.jobs.isEmpty {
                    ProgressView(value: model.controller.aggregateProgress)
                        .frame(width: 190)
                }
            }
            Spacer()
            Button("Batch Metadata…") { isEditingSharedMetadata = true }
                .disabled(selectedIDs.isEmpty || model.controller.isExecuting)
            if model.controller.isExecuting {
                Button("Pause After Current") { model.controller.pauseAfterCurrent() }
            } else {
                Button("Start Conversion") {
                    Task { await model.controller.start() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.jobs.isEmpty || model.destinationDirectory == nil)
            }
        }
        .padding()
    }

    private var destinationDescription: String {
        if let destination = model.destinationDirectory {
            return "Pending output: \(destination.path)"
        }
        return "Choose an output destination before converting."
    }

    private var sharedMetadataSeed: VideoMetadataPatch {
        guard let selected = model.jobs.first(where: { selectedIDs.contains($0.id) }) else { return .init() }
        return selected.sharedMetadata
    }

    private var sharedMetadataProfile: MediaProfile {
        model.jobs.first(where: { selectedIDs.contains($0.id) })?.profile ?? .movie
    }

    private func chooseFiles() {
        guard let urls = NativeOpenPanel.chooseFiles(
            contentTypes: [.data],
            allowsMultipleSelection: true,
            message: "Choose MKV files to add to the conversion queue.",
            prompt: "Add Files"
        ) else { return }
        add(urls)
    }

    private func chooseFolder() {
        guard let folder = NativeOpenPanel.chooseDirectory(
            message: "Choose a folder of MKV files to add recursively.",
            prompt: "Add Folder"
        ) else { return }
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        let files = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: options)?
            .allObjects as? [URL]) ?? []
        add(files)
    }

    private func chooseDestination() {
        guard let folder = NativeOpenPanel.chooseDirectory(
            message: "Choose where converted MP4 files should be saved.",
            prompt: "Choose Output Folder"
        ) else { return }
        model.setDestinationDirectory(folder)
    }

    private func acceptDrop(providers: [NSItemProvider]) -> Bool {
        guard !model.controller.isExecuting else { return false }
        for provider in providers {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async { add([url]) }
            }
        }
        return !providers.isEmpty
    }

    private func add(_ urls: [URL]) {
        do {
            try model.addSources(urls)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var activeErrorMessage: String? {
        errorMessage ?? model.controller.persistenceError
    }

    private func preview(_ job: ConversionJob) {
        previewTarget = PreviewTarget(url: job.status == .completed ? job.destinationURL : job.sourceURL)
    }
}
