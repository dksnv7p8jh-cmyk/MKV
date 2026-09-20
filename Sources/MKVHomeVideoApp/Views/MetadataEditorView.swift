import SwiftUI
import UniformTypeIdentifiers
import MKVHomeVideoCore

struct MetadataEditorView: View {
    let job: ConversionJob
    let save: (MediaProfile, VideoMetadataPatch) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var profile: MediaProfile
    @State private var title: String
    @State private var sortTitle: String
    @State private var descriptionText: String
    @State private var genre: String
    @State private var releaseDate: String
    @State private var collectionName: String
    @State private var director: String
    @State private var cast: String
    @State private var studio: String
    @State private var rating: String
    @State private var copyright: String
    @State private var showName: String
    @State private var showSortName: String
    @State private var episodeTitle: String
    @State private var seasonNumber: String
    @State private var episodeNumber: String
    @State private var episodeSort: String
    @State private var airDate: String
    @State private var network: String
    @State private var artworkURL: URL?
    @State private var clearedFields: Set<MetadataField>

    init(job: ConversionJob, save: @escaping (MediaProfile, VideoMetadataPatch) -> Void) {
        self.job = job
        self.save = save
        let metadata = job.metadataOverride
        _profile = State(initialValue: job.profile)
        _title = State(initialValue: metadata.title ?? "")
        _sortTitle = State(initialValue: metadata.sortTitle ?? "")
        _descriptionText = State(initialValue: metadata.description ?? "")
        _genre = State(initialValue: metadata.genre ?? "")
        _releaseDate = State(initialValue: metadata.releaseDate ?? "")
        _collectionName = State(initialValue: metadata.collectionName ?? "")
        _director = State(initialValue: metadata.director ?? "")
        _cast = State(initialValue: metadata.cast ?? "")
        _studio = State(initialValue: metadata.studio ?? "")
        _rating = State(initialValue: metadata.rating ?? "")
        _copyright = State(initialValue: metadata.copyright ?? "")
        _showName = State(initialValue: metadata.showName ?? "")
        _showSortName = State(initialValue: metadata.showSortName ?? "")
        _episodeTitle = State(initialValue: metadata.episodeTitle ?? "")
        _seasonNumber = State(initialValue: metadata.seasonNumber.map(String.init) ?? "")
        _episodeNumber = State(initialValue: metadata.episodeNumber.map(String.init) ?? "")
        _episodeSort = State(initialValue: metadata.episodeSort.map(String.init) ?? "")
        _airDate = State(initialValue: metadata.airDate ?? "")
        _network = State(initialValue: metadata.network ?? "")
        _artworkURL = State(initialValue: metadata.artworkURL)
        _clearedFields = State(initialValue: metadata.clearedFields)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Profile") {
                    Picker("Metadata profile", selection: $profile) {
                        Text("Movie").tag(MediaProfile.movie)
                        Text("TV Episode").tag(MediaProfile.tvEpisode)
                    }
                    Text("Every export remains an Apple TV Home Video.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Override behavior") {
                    Text("Blank fields inherit the batch value. Use Clear to remove an inherited value for this item.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !clearedFields.isEmpty {
                        Text("Cleared: \(clearedFields.map(\.displayName).sorted().joined(separator: ", "))")
                            .font(.caption)
                    }
                    Menu("Clear inherited field…") {
                        ForEach(MetadataField.allCases) { field in
                            Button(field.displayName) { clear(field) }
                        }
                    }
                    if !clearedFields.isEmpty {
                        Button("Restore all inheritance") { clearedFields.removeAll() }
                    }
                }
                Section("General") {
                    TextField("Title", text: $title)
                    TextField("Sort title", text: $sortTitle)
                    TextField("Genre", text: $genre)
                    TextField("Release date / year", text: $releaseDate)
                    TextField("Collection", text: $collectionName)
                    TextField("Description", text: $descriptionText, axis: .vertical).lineLimit(3...6)
                    TextField("Rating", text: $rating)
                    TextField("Copyright", text: $copyright)
                }
                if profile == .movie {
                    Section("Movie credits") {
                        TextField("Director", text: $director)
                        TextField("Cast", text: $cast)
                        TextField("Studio", text: $studio)
                    }
                } else {
                    Section("TV episode") {
                        TextField("Show name", text: $showName)
                        TextField("Show sort name", text: $showSortName)
                        TextField("Episode title", text: $episodeTitle)
                        TextField("Season number", text: $seasonNumber)
                        TextField("Episode number", text: $episodeNumber)
                        TextField("Episode sort", text: $episodeSort)
                        TextField("Original air date", text: $airDate)
                        TextField("Network", text: $network)
                    }
                }
                Section("Artwork") {
                    HStack {
                        Text(artworkURL?.lastPathComponent ?? "No cover art selected")
                            .lineLimit(1)
                            .foregroundStyle(artworkURL == nil ? .secondary : .primary)
                        Spacer()
                        Button("Choose…", action: chooseArtwork)
                        if artworkURL != nil { Button("Clear") { artworkURL = nil } }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 570, minHeight: 540)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Metadata") {
                    save(profile, patch)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    private var patch: VideoMetadataPatch {
        var effectiveClears = clearedFields
        let stringValues: [(MetadataField, String)] = [
            (.title, title), (.sortTitle, sortTitle), (.description, descriptionText), (.genre, genre),
            (.releaseDate, releaseDate), (.collectionName, collectionName), (.director, director), (.cast, cast),
            (.studio, studio), (.rating, rating), (.copyright, copyright), (.showName, showName),
            (.showSortName, showSortName), (.episodeTitle, episodeTitle), (.airDate, airDate), (.network, network),
        ]
        for (field, value) in stringValues where cleaned(value) != nil { effectiveClears.remove(field) }
        if Int(seasonNumber) != nil { effectiveClears.remove(.seasonNumber) }
        if Int(episodeNumber) != nil { effectiveClears.remove(.episodeNumber) }
        if Int(episodeSort) != nil { effectiveClears.remove(.episodeSort) }
        if artworkURL != nil { effectiveClears.remove(.artwork) }
        return VideoMetadataPatch(
            title: cleaned(title), sortTitle: cleaned(sortTitle), description: cleaned(descriptionText),
            genre: cleaned(genre), releaseDate: cleaned(releaseDate), collectionName: cleaned(collectionName),
            director: cleaned(director), cast: cleaned(cast), studio: cleaned(studio), rating: cleaned(rating),
            copyright: cleaned(copyright), artworkURL: artworkURL, showName: cleaned(showName),
            showSortName: cleaned(showSortName), episodeTitle: cleaned(episodeTitle),
            seasonNumber: Int(seasonNumber), episodeNumber: Int(episodeNumber), episodeSort: Int(episodeSort),
            airDate: cleaned(airDate), network: cleaned(network), clearedFields: effectiveClears
        )
    }

    private func cleaned(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private func clear(_ field: MetadataField) {
        clearedFields.insert(field)
        switch field {
        case .title: title = ""
        case .sortTitle: sortTitle = ""
        case .description: descriptionText = ""
        case .genre: genre = ""
        case .releaseDate: releaseDate = ""
        case .collectionName: collectionName = ""
        case .director: director = ""
        case .cast: cast = ""
        case .studio: studio = ""
        case .rating: rating = ""
        case .copyright: copyright = ""
        case .artwork: artworkURL = nil
        case .showName: showName = ""
        case .showSortName: showSortName = ""
        case .episodeTitle: episodeTitle = ""
        case .seasonNumber: seasonNumber = ""
        case .episodeNumber: episodeNumber = ""
        case .episodeSort: episodeSort = ""
        case .airDate: airDate = ""
        case .network: network = ""
        }
    }

    private func chooseArtwork() {
        artworkURL = NativeOpenPanel.chooseFiles(
            contentTypes: [.jpeg, .png],
            allowsMultipleSelection: false,
            message: "Choose JPEG or PNG cover artwork.",
            prompt: "Choose Artwork"
        )?.first
    }
}

struct SharedMetadataEditorView: View {
    let initialMetadata: VideoMetadataPatch
    let initialProfile: MediaProfile
    let save: (MediaProfile, VideoMetadataPatch) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var profile: MediaProfile = .movie
    @State private var title: String
    @State private var sortTitle: String
    @State private var genre: String
    @State private var collectionName: String
    @State private var descriptionText: String
    @State private var releaseDate: String
    @State private var director: String
    @State private var cast: String
    @State private var studio: String
    @State private var rating: String
    @State private var copyright: String
    @State private var showName: String
    @State private var showSortName: String
    @State private var episodeTitle: String
    @State private var seasonNumber: String
    @State private var episodeNumber: String
    @State private var episodeSort: String
    @State private var airDate: String
    @State private var network: String
    @State private var artworkURL: URL?

    init(
        initialMetadata: VideoMetadataPatch,
        initialProfile: MediaProfile,
        save: @escaping (MediaProfile, VideoMetadataPatch) -> Void
    ) {
        self.initialMetadata = initialMetadata
        self.initialProfile = initialProfile
        self.save = save
        _profile = State(initialValue: initialProfile)
        _title = State(initialValue: initialMetadata.title ?? "")
        _sortTitle = State(initialValue: initialMetadata.sortTitle ?? "")
        _genre = State(initialValue: initialMetadata.genre ?? "")
        _collectionName = State(initialValue: initialMetadata.collectionName ?? "")
        _descriptionText = State(initialValue: initialMetadata.description ?? "")
        _releaseDate = State(initialValue: initialMetadata.releaseDate ?? "")
        _director = State(initialValue: initialMetadata.director ?? "")
        _cast = State(initialValue: initialMetadata.cast ?? "")
        _studio = State(initialValue: initialMetadata.studio ?? "")
        _rating = State(initialValue: initialMetadata.rating ?? "")
        _copyright = State(initialValue: initialMetadata.copyright ?? "")
        _showName = State(initialValue: initialMetadata.showName ?? "")
        _showSortName = State(initialValue: initialMetadata.showSortName ?? "")
        _episodeTitle = State(initialValue: initialMetadata.episodeTitle ?? "")
        _seasonNumber = State(initialValue: initialMetadata.seasonNumber.map(String.init) ?? "")
        _episodeNumber = State(initialValue: initialMetadata.episodeNumber.map(String.init) ?? "")
        _episodeSort = State(initialValue: initialMetadata.episodeSort.map(String.init) ?? "")
        _airDate = State(initialValue: initialMetadata.airDate ?? "")
        _network = State(initialValue: initialMetadata.network ?? "")
        _artworkURL = State(initialValue: initialMetadata.artworkURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Form {
                    Text("These values apply to every selected queued item. Individual metadata can override, inherit, or clear them.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Metadata profile", selection: $profile) {
                        Text("Movie").tag(MediaProfile.movie)
                        Text("TV Episode").tag(MediaProfile.tvEpisode)
                    }
                    Section("General") {
                        TextField("Title", text: $title)
                        TextField("Sort title", text: $sortTitle)
                        TextField("Genre", text: $genre)
                        TextField("Release date / year", text: $releaseDate)
                        TextField("Collection", text: $collectionName)
                        TextField("Description", text: $descriptionText, axis: .vertical).lineLimit(3...6)
                        TextField("Rating", text: $rating)
                        TextField("Copyright", text: $copyright)
                    }
                    if profile == .movie {
                        Section("Movie credits") {
                            TextField("Director", text: $director)
                            TextField("Cast", text: $cast)
                            TextField("Studio", text: $studio)
                        }
                    } else {
                        Section("TV episode") {
                            TextField("Show name", text: $showName)
                            TextField("Show sort name", text: $showSortName)
                            TextField("Episode title", text: $episodeTitle)
                            TextField("Season number", text: $seasonNumber)
                            TextField("Episode number", text: $episodeNumber)
                            TextField("Episode sort", text: $episodeSort)
                            TextField("Original air date", text: $airDate)
                            TextField("Network", text: $network)
                            TextField("Studio", text: $studio)
                        }
                    }
                    Section("Artwork") {
                        HStack {
                            Text(artworkURL?.lastPathComponent ?? "No cover art selected")
                                .lineLimit(1)
                                .foregroundStyle(artworkURL == nil ? .secondary : .primary)
                            Spacer()
                            Button("Choose…", action: chooseArtwork)
                            if artworkURL != nil { Button("Clear") { artworkURL = nil } }
                        }
                    }
                }
                .formStyle(.grouped)
            }
            .frame(width: 580, height: 520)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Apply") {
                    save(profile, patch)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    private var patch: VideoMetadataPatch {
        VideoMetadataPatch(
            title: nonEmpty(title), sortTitle: nonEmpty(sortTitle), description: nonEmpty(descriptionText),
            genre: nonEmpty(genre), releaseDate: nonEmpty(releaseDate), collectionName: nonEmpty(collectionName),
            director: nonEmpty(director), cast: nonEmpty(cast), studio: nonEmpty(studio), rating: nonEmpty(rating),
            copyright: nonEmpty(copyright), artworkURL: artworkURL, showName: nonEmpty(showName),
            showSortName: nonEmpty(showSortName), episodeTitle: nonEmpty(episodeTitle),
            seasonNumber: Int(seasonNumber), episodeNumber: Int(episodeNumber), episodeSort: Int(episodeSort),
            airDate: nonEmpty(airDate), network: nonEmpty(network)
        )
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func chooseArtwork() {
        artworkURL = NativeOpenPanel.chooseFiles(
            contentTypes: [.jpeg, .png],
            allowsMultipleSelection: false,
            message: "Choose JPEG or PNG cover artwork.",
            prompt: "Choose Artwork"
        )?.first
    }
}
