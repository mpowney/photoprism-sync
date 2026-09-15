import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case baseURL, username, password
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("PhotoPrism") {
                    TextField("https://photoprism.example.com", text: $viewModel.settings.baseURLString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .baseURL)
                    TextField("Username", text: $viewModel.settings.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                    SecureField("Password", text: $viewModel.settings.password)
                        .focused($focusedField, equals: .password)
                }

                Section {
                    Button("Save settings") {
                        focusedField = nil
                        viewModel.saveSettings()
                    }
                    .disabled(viewModel.isTestingConnection)

                    Button {
                        focusedField = nil
                        Task {
                            await viewModel.testConnection()
                        }
                    } label: {
                        HStack {
                            Text(viewModel.isTestingConnection ? "Testing connection…" : "Test connection")
                            if viewModel.isTestingConnection {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!viewModel.settings.isComplete || viewModel.isTestingConnection)
                }

                if let status = viewModel.connectionStatus {
                    Section("Connection status") {
                        switch status {
                        case .testing:
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Connecting to PhotoPrism…")
                                    .foregroundStyle(.secondary)
                            }
                        case .success(let message):
                            Label {
                                Text(message)
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        case .failure(let message):
                            Label {
                                Text(message)
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                Section("Notes") {
                    Text("The PhotoPrism server URL and username are stored in app preferences, and the password is stored in the device keychain. Uploads use original asset data so PhotoPrism receives the best available metadata.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .onChange(of: viewModel.settings.baseURLString) { _, _ in viewModel.invalidateCalculation() }
            .onChange(of: viewModel.settings.username) { _, _ in viewModel.invalidateCalculation() }
            .onChange(of: viewModel.settings.password) { _, _ in viewModel.invalidateCalculation() }
        }
    }
}
