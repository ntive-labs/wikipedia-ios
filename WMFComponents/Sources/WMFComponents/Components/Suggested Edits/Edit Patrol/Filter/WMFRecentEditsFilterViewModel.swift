import Foundation
import WMFData
import SwiftUI

/// Filter view model for the Edit Patrol feed. Ports the grouped filter layout of
/// Android's `SuggestedEditsRecentEditsFilterActivity.filterListWithHeaders()` and
/// persists through `WMFRecentEditsDataController`.
public final class WMFRecentEditsFilterViewModel: ObservableObject {

    // MARK: - Strings

    public struct LocalizedStrings {
        public var title: String
        public var doneTitle: String
        public var resetTitle: String
        public var headerUserStatus: String
        public var headerLatestRevisions: String
        public var headerAutomatedContributions: String
        public var headerContributionQuality: String
        public var headerUserIntent: String
        public var headerSignificance: String
        /// App-provided display titles / subtitles for each filter bucket.
        public var typeTitles: [WMFRecentEditsFilterType: String]
        public var typeSubtitles: [WMFRecentEditsFilterType: String]

        public init(title: String, doneTitle: String, resetTitle: String, headerUserStatus: String, headerLatestRevisions: String, headerAutomatedContributions: String, headerContributionQuality: String, headerUserIntent: String, headerSignificance: String, typeTitles: [WMFRecentEditsFilterType: String], typeSubtitles: [WMFRecentEditsFilterType: String]) {
            self.title = title
            self.doneTitle = doneTitle
            self.resetTitle = resetTitle
            self.headerUserStatus = headerUserStatus
            self.headerLatestRevisions = headerLatestRevisions
            self.headerAutomatedContributions = headerAutomatedContributions
            self.headerContributionQuality = headerContributionQuality
            self.headerUserIntent = headerUserIntent
            self.headerSignificance = headerSignificance
            self.typeTitles = typeTitles
            self.typeSubtitles = typeSubtitles
        }
    }

    // MARK: - Group

    public struct Group: Identifiable {
        public let id = UUID()
        public let header: String
        public let types: [WMFRecentEditsFilterType]
        public let isMultiSelect: Bool
    }

    // MARK: - Properties

    public var localizedStrings: LocalizedStrings
    private let dataController: WMFRecentEditsDataController

    @Published public var selected: Set<WMFRecentEditsFilterType>
    @Published public var activeFilterCount: Int

    public let groups: [Group]

    /// Invoked whenever the selection changes, so the feed can refetch (parity with
    /// Android committing the filter and reloading the paging source).
    public var onChange: (() -> Void)?

    // MARK: - Lifecycle

    public init(localizedStrings: LocalizedStrings, dataController: WMFRecentEditsDataController = .shared) {
        self.localizedStrings = localizedStrings
        self.dataController = dataController
        self.selected = dataController.loadFilterSettings().includedTypes
        self.activeFilterCount = dataController.activeFilterCount()
        self.groups = [
            Group(header: localizedStrings.headerUserStatus, types: WMFRecentEditsFilterType.userRegistrationGroup + WMFRecentEditsFilterType.userExperienceGroup, isMultiSelect: true),
            Group(header: localizedStrings.headerLatestRevisions, types: WMFRecentEditsFilterType.latestRevisionsGroup, isMultiSelect: false),
            Group(header: localizedStrings.headerAutomatedContributions, types: WMFRecentEditsFilterType.botEditsGroup, isMultiSelect: false),
            Group(header: localizedStrings.headerContributionQuality, types: WMFRecentEditsFilterType.damagingGroup, isMultiSelect: true),
            Group(header: localizedStrings.headerUserIntent, types: WMFRecentEditsFilterType.goodfaithGroup, isMultiSelect: true),
            Group(header: localizedStrings.headerSignificance, types: WMFRecentEditsFilterType.minorEditsGroup, isMultiSelect: false)
        ]
    }

    // MARK: - Selection

    public func isSelected(_ type: WMFRecentEditsFilterType) -> Bool {
        selected.contains(type)
    }

    public func toggle(_ type: WMFRecentEditsFilterType) {
        guard let group = groups.first(where: { $0.types.contains(type) }) else { return }

        if group.isMultiSelect {
            if selected.contains(type) {
                selected.remove(type)
            } else {
                selected.insert(type)
            }
        } else {
            // Single-select: replace the group's selection with the tapped type.
            for member in group.types {
                selected.remove(member)
            }
            selected.insert(type)
        }
        persist()
    }

    public func reset() {
        selected = WMFRecentEditsFilterType.defaultFilterTypeSet
        persist()
    }

    private func persist() {
        dataController.saveFilterSettings(WMFRecentEditsFilterSettings(includedTypes: selected))
        activeFilterCount = dataController.activeFilterCount()
        onChange?()
    }

    // MARK: - Display helpers

    public func title(for type: WMFRecentEditsFilterType) -> String {
        localizedStrings.typeTitles[type] ?? type.id
    }

    public func subtitle(for type: WMFRecentEditsFilterType) -> String? {
        localizedStrings.typeSubtitles[type]
    }
}
