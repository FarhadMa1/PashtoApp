import Testing
import PashtoCore
import PashtoCoreTesting

struct ProgressStoreTests {
    @Test func inMemoryProgressStoreMeetsTheContract() async throws {
        try await ProgressStoreContract.run {
            InMemoryProgressStore(contentVersion: "2026.11.0")
        }
    }

    @Test func oneCardPerItemID() async throws {
        try await ProgressStoreContract.oneCardPerItemID(InMemoryProgressStore())
    }

    @Test func resetProgressClearsEverything() async throws {
        try await ProgressStoreContract.resetClearsLearnerProgress(
            InMemoryProgressStore(contentVersion: "2026.11.0")
        )
    }

    @Test func aFailedCommitKeepsTheActiveSession() async throws {
        try await ProgressStoreContract.runWriteFailure(CommitRejectingProgressStore())
    }
}
