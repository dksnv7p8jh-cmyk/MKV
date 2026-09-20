import Foundation

public enum MediaFileIntake {
    public static func mkvFiles(in urls: [URL]) -> [URL] {
        urls.filter { $0.pathExtension.caseInsensitiveCompare("mkv") == .orderedSame }
    }
}
