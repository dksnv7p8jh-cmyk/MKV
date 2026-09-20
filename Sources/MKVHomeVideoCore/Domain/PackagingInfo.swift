import Foundation

public struct PackagingInfo: Sendable, Equatable {
    public let bundleIdentifier: String
    public let minimumSystemVersion: String

    public static func load(fromRepositoryRoot root: String) throws -> PackagingInfo {
        let fileURL = URL(filePath: root)
            .appending(path: "Resources", directoryHint: .isDirectory)
            .appending(path: "Info.plist")
        let data = try Data(contentsOf: fileURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dictionary = plist as? [String: Any],
              let bundleIdentifier = dictionary["CFBundleIdentifier"] as? String,
              let minimumSystemVersion = dictionary["LSMinimumSystemVersion"] as? String else {
            throw PackagingInfoError.invalidInfoPlist
        }
        return PackagingInfo(
            bundleIdentifier: bundleIdentifier,
            minimumSystemVersion: minimumSystemVersion
        )
    }
}

public enum PackagingInfoError: Error, Sendable, Equatable {
    case invalidInfoPlist
}
