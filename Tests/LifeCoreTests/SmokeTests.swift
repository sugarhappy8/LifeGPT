import Testing
@testable import LifeCore

@Test func versionIsNonEmpty() {
    #expect(!LifeCore.version.isEmpty)
}
