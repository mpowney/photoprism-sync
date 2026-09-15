import SwiftUI

struct CriteriaFormView: View {
    enum DuplicateMode {
        case hidden
        case optional
        case required
    }

    @Binding var criteria: SyncCriteria
    let showsAgeRule: Bool
    let duplicateMode: DuplicateMode
    let duplicateHelpText: String?
    let sectionTitle: String

    private var ageRuleEnabled: Binding<Bool> {
        Binding(
            get: { criteria.ageRule != nil },
            set: { isEnabled in
                if isEnabled {
                    criteria.ageRule = criteria.ageRule ?? AgeRule()
                } else {
                    criteria.ageRule = nil
                }
            }
        )
    }

    var body: some View {
        Section(sectionTitle) {
            if showsAgeRule {
                Toggle("Only include items older than…", isOn: ageRuleEnabled)

                if criteria.ageRule != nil {
                    Stepper(value: ageRuleValueBinding, in: 1 ... 3650) {
                        Text("Value: \(criteria.ageRule?.value ?? 0)")
                    }

                    Picker("Unit", selection: ageRuleUnitBinding) {
                        ForEach(TimeUnit.allCases) { unit in
                            Text(unit.rawValue.capitalized).tag(unit)
                        }
                    }
                }
            }

            Toggle("Photos", isOn: photosBinding)
            Toggle("Live Photos", isOn: livePhotosBinding)
            Toggle("Videos", isOn: videosBinding)
        }

        switch duplicateMode {
        case .hidden:
            EmptyView()
        case .optional:
            Section(header: Text("Duplicates"), footer: duplicateHelpText.map(Text.init)) {
                Toggle("Avoid duplicates", isOn: avoidDuplicatesBinding)
                if criteria.avoidDuplicates {
                    duplicateCriteriaToggles
                }
            }
        case .required:
            Section("How to match duplicates") {
                duplicateCriteriaToggles
            }
        }
    }

    private var duplicateCriteriaToggles: some View {
        Group {
            duplicateToggle(for: .filename, title: "By filename")
            duplicateToggle(for: .photoTimestamp, title: "By photo timestamp")
        }
    }

    private func duplicateToggle(for criterion: DuplicateCriterion, title: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { criteria.duplicateCriteria.contains(criterion) },
            set: { enabled in
                if enabled {
                    criteria.duplicateCriteria.insert(criterion)
                } else {
                    criteria.duplicateCriteria.remove(criterion)
                }
            }
        ))
    }

    private var ageRuleValueBinding: Binding<Int> {
        Binding(
            get: { criteria.ageRule?.value ?? 30 },
            set: { criteria.ageRule = AgeRule(value: $0, unit: criteria.ageRule?.unit ?? .days) }
        )
    }

    private var ageRuleUnitBinding: Binding<TimeUnit> {
        Binding(
            get: { criteria.ageRule?.unit ?? .days },
            set: { criteria.ageRule = AgeRule(value: criteria.ageRule?.value ?? 30, unit: $0) }
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
