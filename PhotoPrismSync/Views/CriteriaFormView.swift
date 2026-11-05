import SwiftUI

struct CriteriaFormView: View {
    enum DuplicateMode {
        case hidden
        case optional
        case delete
        case required
    }

    @Binding var criteria: SyncCriteria
    @Binding var timestampFilterSettings: TimestampFilterSettings
    let duplicateMode: DuplicateMode
    let sectionTitle: LocalizedStringKey

    private var timestampFilterEnabled: Binding<Bool> {
        Binding(
            get: { timestampFilterSettings.isEnabled },
            set: { timestampFilterSettings.isEnabled = $0 }
        )
    }

    var body: some View {
        Section(sectionTitle) {
            Toggle("Photos", isOn: photosBinding)
            Toggle("Live Photos", isOn: livePhotosBinding)
            Toggle("Videos", isOn: videosBinding)
        }

        Section {
            Toggle("Filter sync by photo's timestamp", isOn: timestampFilterEnabled)

            if timestampFilterSettings.isEnabled {
                Picker("Photo date range", selection: timestampFilterPresetBinding) {
                    ForEach(TimestampFilterPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }

                DatePicker("Start date", selection: timestampFilterStartDateBinding, displayedComponents: .date)
                DatePicker("End date", selection: timestampFilterEndDateBinding, displayedComponents: .date)
            }
        }

        switch duplicateMode {
        case .hidden:
            EmptyView()
        case .optional:
            Section("Duplicates") {
                Toggle("Avoid duplicates", isOn: avoidDuplicatesBinding)
                Text("Duplicates are determined by your selected duplicate matching settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .delete:
            Section("Duplicates") {
                Toggle("Delete duplicates", isOn: avoidDuplicatesBinding)
                Text("When enabled, duplicates are determined by your selected duplicate matching settings; matching photos are deleted from your iPhone only, not from PhotoPrism.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .required:
            Section("Duplicates") {
                Text("Your selected duplicate matching settings determine which local photos match PhotoPrism. Matching photos are deleted from your iPhone only, not from PhotoPrism.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timestampFilterPresetBinding: Binding<TimestampFilterPreset> {
        Binding(
            get: { timestampFilterSettings.preset },
            set: { preset in
                var updated = timestampFilterSettings
                updated.select(preset)
                timestampFilterSettings = updated
            }
        )
    }

    private var timestampFilterStartDateBinding: Binding<Date> {
        Binding(
            get: { timestampFilterSettings.startDate },
            set: { date in
                var updated = timestampFilterSettings
                updated.setStartDate(date)
                timestampFilterSettings = updated
            }
        )
    }

    private var timestampFilterEndDateBinding: Binding<Date> {
        Binding(
            get: { timestampFilterSettings.endDate },
            set: { date in
                var updated = timestampFilterSettings
                updated.setEndDate(date)
                timestampFilterSettings = updated
            }
        )
    }

    private var photosBinding: Binding<Bool> {
        Binding(
            get: { criteria.mediaSelection.includePhotos },
            set: { criteria.mediaSelection.includePhotos = $0 }
        )
    }

    private var livePhotosBinding: Binding<Bool> {
        Binding(
            get: { criteria.mediaSelection.includeLivePhotos },
            set: { criteria.mediaSelection.includeLivePhotos = $0 }
        )
    }

    private var videosBinding: Binding<Bool> {
        Binding(
            get: { criteria.mediaSelection.includeVideos },
            set: { criteria.mediaSelection.includeVideos = $0 }
        )
    }

    private var avoidDuplicatesBinding: Binding<Bool> {
        Binding(
            get: { criteria.avoidDuplicates },
            set: { criteria.avoidDuplicates = $0 }
        )
    }
}
