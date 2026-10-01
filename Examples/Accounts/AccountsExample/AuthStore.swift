import Foundation
import Observation
import Reception

@Observable @MainActor
final class AuthStore {
    private(set) var userId: String?
    private(set) var name: String?
    private(set) var email: String?
    private(set) var isDeleting = false
    private(set) var deletionError: String?

    private let defaults = UserDefaults.standard
    private let userIdKey = "accounts-example.userId"
    private let nameKey = "accounts-example.name"
    private let emailKey = "accounts-example.email"

    func restoreSession() {
        guard let storedUserId = defaults.string(forKey: userIdKey) else { return }
        userId = storedUserId
        name = defaults.string(forKey: nameKey)
        email = defaults.string(forKey: emailKey)
        identifySupport()
    }

    func signIn(name: String, email: String) {
        let stableUserId = defaults.string(forKey: userIdKey) ?? UUID().uuidString
        defaults.set(stableUserId, forKey: userIdKey)
        defaults.set(name, forKey: nameKey)
        defaults.set(email, forKey: emailKey)
        userId = stableUserId
        self.name = name
        self.email = email
        identifySupport()
    }

    func signOut() {
        // identify(token:) never replaces logout(): it revokes the support session before local state is cleared.
        Reception.shared.logout()
        clearLocal()
    }

    func deleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        deletionError = nil
        defer { isDeleting = false }

        do {
            // deleteData() must complete before logout(), which would forget the session it deletes.
            try await Reception.shared.deleteData()
            Reception.shared.logout()
            clearLocal()
        } catch let error as ReceptionError {
            deletionError = "Could not delete your account (\(error.code)). Please try again."
        } catch {
            deletionError = "Could not delete your account. Please try again."
        }
    }

    /// An expired token gets a fresh one. Other rejections point at the server's identity secret setup.
    func supportIdentityRejected(_ error: ReceptionError) {
        if error.code == "identity_token_expired" { identifySupport() }
    }

    /// Verified when your server signs a token; otherwise the unverified fallback labels the chat.
    private func identifySupport() {
        guard let userId else { return }
        let name = name
        let email = email
        Task {
            let token = try? await fetchReceptionToken(userId: userId)
            guard self.userId == userId else { return }
            if let token {
                Reception.shared.identify(token: token)
            } else {
                Reception.shared.identify(userId: userId, name: name, email: email)
            }
        }
    }

    // MARK: - Your server

    /// Fetches a Reception identity token from your own server. The server checks the app's session and signs
    /// `{ user_id, name, email, exp }` with the identity secret from the Reception dashboard (HS256).
    /// The identity secret never belongs in the app. Without a token URL this example stays unverified.
    private func fetchReceptionToken(userId: String) async throws -> String? {
        guard let address = MaintainerSettings.value("RECEPTION_TOKEN_URL", argument: "-ReceptionTokenURL"),
              let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // This example's session credential is its local user id. Send your app's real session credential instead.
        request.setValue("Bearer " + userId, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        struct Reply: Decodable { let token: String }
        return try JSONDecoder().decode(Reply.self, from: data).token
    }

    private func clearLocal() {
        defaults.removeObject(forKey: userIdKey)
        defaults.removeObject(forKey: nameKey)
        defaults.removeObject(forKey: emailKey)
        userId = nil
        name = nil
        email = nil
    }
}
