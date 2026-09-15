import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        TabView {
            NavigationStack {
                Form {
                    Section("Action") {
                        Picker("Action", selection: $viewModel.selectedAction) {
                            ForEach(AppViewModel.PrimaryAction.allCases) { action in
                                Text(action.title).tag(action)
                            }
                        }
                        .pickerStyle(.segmented)

                        if viewModel.selectedAction == .delete {
                            Picker("Delete mode", selection: $viewModel.deleteMode) {
                                ForEach(AppViewModel.DeleteMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                        }
                    }

                    CriteriaFormView(
                        criteria: $viewModel.criteria,
                        showsAgeRule: viewModel.currentAction != .deleteFoundInPhotoPrism,
                        duplicateMode: viewModel.currentAction == .deleteFoundInPhotoPrism ? .required : .optional,
                        duplicateHelpText: viewModel.selectedAction == .delete && viewModel.deleteMode == .olderThan ? "When enabled, duplicate checks compare your local library against PhotoPrism and require server credentials." : nil,
                        sectionTitle: viewModel.selectedAction == .delete ? "What to delete" : "What to include"
                    )

                    if let snapshot = viewModel.calculationSnapshot {
                        Section("Calculated selection") {
                            LabeledContent("Items", value: "\(snapshot.summary.itemCount)")
                            LabeledContent("Total size", value: viewModel.formattedSize(snapshot.summary.totalBytes))
                            LabeledContent("Prepared at", value: snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }

                    Section {
                        Button("Calculate") {
                            Task {
                                await viewModel.calculateSelection()
                            }
                        }
                        .disabled(viewModel.isCalculating || viewModel.isExecuting)

                        Button("Preview") {
                            viewModel.isShowingPreview = true
                        }
                        .disabled(viewModel.previewItems.isEmpty)

                        Button(viewModel.executeButtonTitle) {
                            Task {
                                await viewModel.executeCalculatedSelection()
                            }
                        }
                        .disabled(viewModel.calculationSnapshot == nil || viewModel.isCalculating || viewModel.isExecuting)
                    }

                    if !viewModel.progressMessage.isEmpty {
                        Section("Status") {
                            if viewModel.isCalculating || viewModel.isExecuting {
                                ProgressView(value: progressFraction)
                            }
                            Text(viewModel.progressMessage)
                            if viewModel.totalItems > 0 {
                                Text("\(viewModel.completedItems) of \(viewModel.totalItems) processed")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !viewModel.noticeMessage.isEmpty {
                        Section("Last result") {
                            Text(viewModel.noticeMessage)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("PhotoPrism Sync")
            }
            .tabItem {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }

            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .onChange(of: viewModel.selectedAction) { _, _ in
            viewModel.invalidateCalculation()
        }
        .onChange(of: viewModel.deleteMode) { _, _ in
            viewModel.invalidateCalculation()
        }
        .onChange(of: viewModel.criteria) { _, _ in
            viewModel.invalidateCalculation()
        }
        .sheet(isPresented: $viewModel.isShowingPreview) {
            PreviewGridView(items: viewModel.previewItems, formattedSize: viewModel.formattedSize)
        }
        .alert("Error", isPresented: errorBinding, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        })
    }

    private var progressFraction: Double {
        guard viewModel.totalItems > 0 else { return 0 }
        return Double(viewModel.completedItems) / Double(viewModel.totalItems)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                }
            }
        )
    }
}
