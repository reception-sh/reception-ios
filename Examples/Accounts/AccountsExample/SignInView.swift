import SwiftUI

@MainActor
struct SignInView: View {
    var authStore: AuthStore
    @State private var name = ""
    @State private var email = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Button("Sign in") {
                        authStore.signIn(name: name, email: email)
                    }
                    .disabled(name.isEmpty || email.isEmpty)
                }
            }
            .navigationTitle("Sign in")
        }
    }
}
