import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isShowingSettings = false
    @State private var isConfirmingDelete = false
    @State private var pendingDeleteItems: [AssetDescriptor] = []

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    syncForm
                        .navigationTitle("PhotoPrism Sync")
                        .toolbar {
                            settingsToolbarItem
                            actionToolbarItems
                        }
                } detail: {
                    regularPreview
                }
            } else {
                NavigationStack {
                    syncForm
                        .navigationTitle("PhotoPrism Sync")
                        .toolbar {
                            settingsToolbarItem
                            actionToolbarItems
                        }
                }
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
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isShowingPreview) {
            NavigationStack {
                PreviewPanelView(
                    items: viewModel.previewItems,
                    matchedItems: viewModel.matchedItems,
                    formattedSize: viewModel.formattedSize,
                    onSync: requestExecution,
                    syncButtonTitle: viewModel.executeButtonTitle,
                    isDestructive: viewModel.selectedAction == .delete
                )
            }
        }
        .confirmationDialog(
            "Delete \(pendingDeleteItems.count) selected photos from your iPhone?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Photos", role: .destructive) {
                executeSelectedItems(pendingDeleteItems)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected photos from your device.")
        }
        .alert("Error", isPresented: errorBinding, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        })
    }

    private var syncForm: some View {
        Form {
            if !viewModel.settings.isComplete {
                Section {
                    Label("Connect your PhotoPrism library", systemImage: "person.crop.circle.badge.plus")
                        .font(.headline)
                    Text("Add your server URL and credentials in Settings. Photos access is requested when you calculate a local selection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        isShowingSettings = true
                    }
                }
            }

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
                    if snapshot.items.isEmpty {
                        Text("No items match these filters. Adjust your criteria and calculate again.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        viewModel.isShowingPreview = true
                    } label: {
                        Label("Preview \(snapshot.summary.itemCount) items", systemImage: "square.grid.3x3")
                    }
                }
            }

            if !viewModel.progressMessage.isEmpty {
                Section("Status") {
                    if viewModel.isCalculating || viewModel.isExecuting {
                        ProgressView(value: progressFraction)
                            .accessibilityLabel("Sync progress")
                    }
                    Text(viewModel.progressMessage)
                        .font(.subheadline)
                    if viewModel.totalItems > 0 {
                        Text("\(viewModel.completedItems) of \(viewModel.totalItems) processed")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !viewModel.noticeMessage.isEmpty {
                Section("Last result") {
                    Label(viewModel.noticeMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .refreshable {
            await viewModel.calculateSelection()
        }
    }

    @ToolbarContentBuilder
    private var settingsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isShowingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    @ToolbarContentBuilder
    private var actionToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                viewModel.isShowingPreview = true
            } label: {
                Label("Preview", systemImage: "square.grid.3x3")
            }

            Button(action: performPrimaryAction) {
                Group {
                    if viewModel.isCalculating || viewModel.isExecuting {
                        ProgressView()
                    } else {
                        Text(primaryActionTitle)
                    }
                }
            }
            .tint(viewModel.selectedAction == .delete && viewModel.calculationSnapshot != nil ? .red : nil)
            .disabled(viewModel.isCalculating || viewModel.isExecuting || (viewModel.calculationSnapshot != nil && viewModel.previewItems.isEmpty))
        }
    }

    private var regularPreview: some View {
        Group {
            if let snapshot = viewModel.calculationSnapshot {
                PreviewPanelView(
                    items: snapshot.items,
                    matchedItems: viewModel.matchedItems,
                    formattedSize: viewModel.formattedSize,
                    onSync: requestExecution,
                    syncButtonTitle: viewModel.executeButtonTitle,
                    isDestructive: viewModel.selectedAction == .delete,
                    showsDoneButton: false
                )
            } else {
                ContentUnavailableView(
                    "Calculate a Selection",
                    systemImage: "square.grid.3x3",
                    description: Text("Your matching photos and videos will appear here.")
                )
            }
        }
        .navigationTitle("Preview")
    }

    private var primaryActionTitle: String {
        viewModel.calculationSnapshot == nil ? "Calculate" : viewModel.executeButtonTitle
    }

    private var progressFraction: Double {
        guard viewModel.totalItems > 0 else { return 0 }
        return Double(viewModel.completedItems) / Double(viewModel.totalItems)
    }

    private func performPrimaryAction() {
        guard viewModel.calculationSnapshot != nil else {
            Task {
                await viewModel.calculateSelection()
            }
            return
        }

        requestExecution(items: viewModel.previewItems)
    }

    private func requestExecution(items: [AssetDescriptor]) {
        guard !items.isEmpty else { return }
        if viewModel.selectedAction == .delete {
            pendingDeleteItems = items
            isConfirmingDelete = true
        } else {
            executeSelectedItems(items)
        }
    }

    private func executeSelectedItems(_ items: [AssetDescriptor]) {
        viewModel.isShowingPreview = false
        Task {
            await viewModel.executeCalculatedSelection(items: items)
        }
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
