import Foundation

public enum MediaProfile: String, Codable, CaseIterable, Sendable, Equatable {
    case movie
    case tvEpisode
}

public enum AppleMediaKind: Int, Codable, Sendable, Equatable {
    case homeVideo = 10
}

public enum MetadataField: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case title, sortTitle, description, genre, releaseDate, collectionName
    case director, cast, studio, rating, copyright, artwork
    case showName, showSortName, episodeTitle, seasonNumber, episodeNumber, episodeSort, airDate, network

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .title: "Title"
        case .sortTitle: "Sort title"
        case .description: "Description"
        case .genre: "Genre"
        case .releaseDate: "Release date / year"
        case .collectionName: "Collection"
        case .director: "Director"
        case .cast: "Cast"
        case .studio: "Studio"
        case .rating: "Rating"
        case .copyright: "Copyright"
        case .artwork: "Artwork"
        case .showName: "Show name"
        case .showSortName: "Show sort name"
        case .episodeTitle: "Episode title"
        case .seasonNumber: "Season number"
        case .episodeNumber: "Episode number"
        case .episodeSort: "Episode sort"
        case .airDate: "Original air date"
        case .network: "Network"
        }
    }
}

public struct VideoMetadataPatch: Codable, Sendable, Equatable {
    public var title: String?
    public var sortTitle: String?
    public var description: String?
    public var genre: String?
    public var releaseDate: String?
    public var collectionName: String?
    public var director: String?
    public var cast: String?
    public var studio: String?
    public var rating: String?
    public var copyright: String?
    public var artworkURL: URL?
    public var showName: String?
    public var showSortName: String?
    public var episodeTitle: String?
    public var seasonNumber: Int?
    public var episodeNumber: Int?
    public var episodeSort: Int?
    public var airDate: String?
    public var network: String?
    public var clearedFields: Set<MetadataField>

    public init(
        title: String? = nil,
        sortTitle: String? = nil,
        description: String? = nil,
        genre: String? = nil,
        releaseDate: String? = nil,
        collectionName: String? = nil,
        director: String? = nil,
        cast: String? = nil,
        studio: String? = nil,
        rating: String? = nil,
        copyright: String? = nil,
        artworkURL: URL? = nil,
        showName: String? = nil,
        showSortName: String? = nil,
        episodeTitle: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeSort: Int? = nil,
        airDate: String? = nil,
        network: String? = nil,
        clearedFields: Set<MetadataField> = []
    ) {
        self.title = title
        self.sortTitle = sortTitle
        self.description = description
        self.genre = genre
        self.releaseDate = releaseDate
        self.collectionName = collectionName
        self.director = director
        self.cast = cast
        self.studio = studio
        self.rating = rating
        self.copyright = copyright
        self.artworkURL = artworkURL
        self.showName = showName
        self.showSortName = showSortName
        self.episodeTitle = episodeTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeSort = episodeSort
        self.airDate = airDate
        self.network = network
        self.clearedFields = clearedFields
    }
}

public typealias VideoMetadata = VideoMetadataPatch

public struct ResolvedVideoMetadata: Sendable, Equatable {
    public let profile: MediaProfile
    public let mediaKind: AppleMediaKind
    public let title: String?
    public let sortTitle: String?
    public let description: String?
    public let genre: String?
    public let releaseDate: String?
    public let collectionName: String?
    public let director: String?
    public let cast: String?
    public let studio: String?
    public let rating: String?
    public let copyright: String?
    public let artworkURL: URL?
    public let showName: String?
    public let showSortName: String?
    public let episodeTitle: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let episodeSort: Int?
    public let airDate: String?
    public let network: String?

    public init(profile: MediaProfile, shared: VideoMetadataPatch, override: VideoMetadataPatch) {
        self.profile = profile
        self.mediaKind = .homeVideo
        self.title = Self.resolved(.title, override.title, shared.title, override.clearedFields)
        self.sortTitle = Self.resolved(.sortTitle, override.sortTitle, shared.sortTitle, override.clearedFields)
        self.description = Self.resolved(.description, override.description, shared.description, override.clearedFields)
        self.genre = Self.resolved(.genre, override.genre, shared.genre, override.clearedFields)
        self.releaseDate = Self.resolved(.releaseDate, override.releaseDate, shared.releaseDate, override.clearedFields)
        self.collectionName = Self.resolved(.collectionName, override.collectionName, shared.collectionName, override.clearedFields)
        self.director = Self.resolved(.director, override.director, shared.director, override.clearedFields)
        self.cast = Self.resolved(.cast, override.cast, shared.cast, override.clearedFields)
        self.studio = Self.resolved(.studio, override.studio, shared.studio, override.clearedFields)
        self.rating = Self.resolved(.rating, override.rating, shared.rating, override.clearedFields)
        self.copyright = Self.resolved(.copyright, override.copyright, shared.copyright, override.clearedFields)
        self.artworkURL = Self.resolved(.artwork, override.artworkURL, shared.artworkURL, override.clearedFields)
        self.showName = Self.resolved(.showName, override.showName, shared.showName, override.clearedFields)
        self.showSortName = Self.resolved(.showSortName, override.showSortName, shared.showSortName, override.clearedFields)
        self.episodeTitle = Self.resolved(.episodeTitle, override.episodeTitle, shared.episodeTitle, override.clearedFields)
        self.seasonNumber = Self.resolved(.seasonNumber, override.seasonNumber, shared.seasonNumber, override.clearedFields)
        self.episodeNumber = Self.resolved(.episodeNumber, override.episodeNumber, shared.episodeNumber, override.clearedFields)
        self.episodeSort = Self.resolved(.episodeSort, override.episodeSort, shared.episodeSort, override.clearedFields)
        self.airDate = Self.resolved(.airDate, override.airDate, shared.airDate, override.clearedFields)
        self.network = Self.resolved(.network, override.network, shared.network, override.clearedFields)
    }

    private static func resolved<Value>(
        _ field: MetadataField,
        _ overrideValue: Value?,
        _ sharedValue: Value?,
        _ clearedFields: Set<MetadataField>
    ) -> Value? {
        clearedFields.contains(field) ? nil : (overrideValue ?? sharedValue)
    }
}
