import Foundation

public enum CriteriaEvaluator {
    public static func matchingDuplicates(
        sourceItems: [AssetDescriptor],
        criteria: SyncCriteria,
        duplicateReferenceItems: [AssetDescriptor],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [AssetDescriptor] {
        let cutoff = criteria.ageRule?.cutoffDate(relativeTo: now, calendar: calendar)
        let effectiveCriteria = criteria.effectiveDuplicateCriteria.isEmpty ? Set(DuplicateCriterion.allCases) : criteria.effectiveDuplicateCriteria
        let duplicateIndex = buildDuplicateIndex(from: duplicateReferenceItems, criteria: effectiveCriteria)

        return sourceItems.filter { item in
            guard criteria.mediaSelection.matches(item.mediaKind) else {
                return false
            }

            if let cutoff {
                guard let capturedAt = item.capturedAt, capturedAt <= cutoff else {
                    return false
                }
            }

            return duplicateKeys(for: item, criteria: effectiveCriteria).contains { duplicateIndex.contains($0) }
        }
    }

    public static func filter(
        sourceItems: [AssetDescriptor],
        criteria: SyncCriteria,
        duplicateReferenceItems: [AssetDescriptor] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [AssetDescriptor] {
        let cutoff = criteria.ageRule?.cutoffDate(relativeTo: now, calendar: calendar)
        let duplicateIndex = buildDuplicateIndex(from: duplicateReferenceItems, criteria: criteria.effectiveDuplicateCriteria)

        return sourceItems.filter { item in
            guard criteria.mediaSelection.matches(item.mediaKind) else {
                return false
            }

            if let cutoff {
                guard let capturedAt = item.capturedAt, capturedAt <= cutoff else {
                    return false
                }
            }

            guard !criteria.avoidDuplicates || duplicateIndex.isEmpty else {
                return !duplicateKeys(for: item, criteria: criteria.effectiveDuplicateCriteria).contains { duplicateIndex.contains($0) }
            }

            return true
        }
    }

    public static func buildDuplicateIndex(
        from items: [AssetDescriptor],
        criteria: Set<DuplicateCriterion>
    ) -> Set<String> {
        Set(items.flatMap { duplicateKeys(for: $0, criteria: criteria) })
    }

    public static func duplicateKeys(
        for item: AssetDescriptor,
        criteria: Set<DuplicateCriterion>
    ) -> [String] {
        criteria.compactMap { criterion in
            switch criterion {
            case .filename:
                let name = item.filenameForComparison.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return name.isEmpty ? nil : "filename:\(name)"
            case .photoTimestamp:
                guard let capturedAt = item.capturedAt else { return nil }
                let seconds = Int(capturedAt.timeIntervalSince1970.rounded())
                return "photoTimestamp:\(seconds)"
            }
        }
    }
}
