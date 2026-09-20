import Foundation

public enum FFmpegMetadataTagMapper {
    public static func arguments(for metadata: ResolvedVideoMetadata) -> [String] {
        var arguments: [String] = []

        func append(_ key: String, _ value: String?) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
            arguments += ["-metadata", "\(key)=\(value)"]
        }

        append("title", metadata.title ?? metadata.episodeTitle)
        append("sort_name", metadata.sortTitle ?? metadata.showSortName)
        append("description", metadata.description)
        append("genre", metadata.genre)
        append("date", metadata.profile == .tvEpisode ? metadata.airDate ?? metadata.releaseDate : metadata.releaseDate)
        append("album", metadata.collectionName)
        append("artist", metadata.cast)
        append("album_artist", metadata.director)
        append("publisher", metadata.studio)
        append("rating", metadata.rating)
        append("copyright", metadata.copyright)
        append("show", metadata.showName)
        append("episode_id", metadata.episodeTitle)
        append("season_number", metadata.seasonNumber.map(String.init))
        append("episode_sort", (metadata.episodeSort ?? metadata.episodeNumber).map(String.init))
        append("network", metadata.network)
        append("media_type", String(metadata.mediaKind.rawValue))
        return arguments
    }
}
