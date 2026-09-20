import Testing
@testable import MKVHomeVideoCore

@Test("the core package exposes its app identity")
func appIdentityIsStable() {
    #expect(AppIdentity.bundleIdentifier == "com.peterbertella.MKVHomeVideo")
}
