import Observation
import Reception

@MainActor @Observable
final class DataDeletion {
    var isDeleting = false
    var error: String?

    func delete() {
        guard !isDeleting else { return }
        isDeleting = true
        error = nil
        Task {
            defer { isDeleting = false }
            do { try await Reception.shared.deleteData() }
            catch { self.error = "Could not delete your data. Please try again." }
        }
    }
}
