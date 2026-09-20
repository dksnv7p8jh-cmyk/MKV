import Foundation
import Testing
@testable import MKVHomeVideoCore

@Test("bundle plist agrees with the core app identity")
func plistUsesAppIdentity() throws {
    let root = try #require(ProcessInfo.processInfo.environment["MKV_REPOSITORY_ROOT"])
    let plist = try PackagingInfo.load(fromRepositoryRoot: root)

    #expect(plist.bundleIdentifier == AppIdentity.bundleIdentifier)
    #expect(plist.minimumSystemVersion == "26.0")
}
