import Testing
@testable import PashtoCore

@Test func moduleNameIsStable() {
    #expect(PashtoCore.moduleName == "PashtoCore")
}
