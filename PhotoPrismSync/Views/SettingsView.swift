import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("PhotoPrism") {
                    TextField("https://photoprism.example.com", text: $viewModel.settings.baseURLString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("Username", text: $viewModel.settings.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $viewModel.settings.password)
                }

                Section {
                    Button("Save settings") {
                        viewModel.saveSettings()
                    }

                    Button("Test connection") {
                        Task {
                            await viewModel.testConnection()
                        }
                    }
                    .disabled(!viewModel.settings.isComplete)
                }

                Section("Notes") {
                    Text("Credentials are kept in the device keychain. Uploads use original asset data so PhotoPrism receives the best available metadata.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
