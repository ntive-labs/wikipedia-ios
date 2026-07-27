import Foundation

/// Persisted Edit Patrol filter selection.
///
/// Android stores the active filters as a flat set of type codes
/// (`Prefs.recentEditsIncludedTypeCodes`). We mirror that model directly with a
/// `Set<WMFRecentEditsFilterType>` so the ported filtering/counting logic reads
/// the same and stays parity-correct. Defaults match Android's
/// `DEFAULT_FILTER_TYPE_SET`.
public struct WMFRecentEditsFilterSettings: Codable, Equatable, Sendable {

    public var includedTypes: Set<WMFRecentEditsFilterType>

    public init(includedTypes: Set<WMFRecentEditsFilterType> = WMFRecentEditsFilterType.defaultFilterTypeSet) {
        self.includedTypes = includedTypes
    }

    public var isDefault: Bool {
        includedTypes == WMFRecentEditsFilterType.defaultFilterTypeSet
    }

    /// Convenience: whether any ORES (damaging/good-faith) bucket is selected.
    public var hasActiveORESFilter: Bool {
        let oresGroup = Set(WMFRecentEditsFilterType.damagingGroup + WMFRecentEditsFilterType.goodfaithGroup)
        return !includedTypes.isDisjoint(with: oresGroup)
    }
}
