import Foundation
import WMFData
import SwiftUI

/// Delegate that surfaces feed interactions back to the app-side (coordinator).
/// Mirrors the Watchlist delegate pattern; the app conforms and performs the
/// actual navigation (diff, user page, filter screen).
public protocol WMFRecentEditsDelegate: AnyObject {
    /// The patroller tapped an edit row. `allItems` is the full, ordered feed and
    /// `index` is the tapped row's position, so the app can seed the revert-candidate
    /// cache with `allItems[0...index]` before opening the diff (parity with Android's
    /// `populateEditingSuggestionsProvider`).
    func recentEditsDidTapItem(_ item: WMFRecentEditsViewModel.ItemViewModel, allItems: [WMFRecentEditsViewModel.ItemViewModel], index: Int)
    func recentEditsDidTapFilter()
    func recentEditsDidTapUser(username: String, project: WMFProject)
}

/// Feed view model for the Edit Patrol recent-changes list. Structurally modeled on
/// `WMFWatchlistViewModel` (day-bucketed sections, item view models, local search)
/// and backed by `WMFRecentEditsDataController`.
public final class WMFRecentEditsViewModel: ObservableObject {

    // MARK: - Localized strings

    public struct LocalizedStrings {
        public var title: String
        public var searchPlaceholder: String
        public var filter: String
        public var emptyTitle: String
        public var emptySubtitle: String
        public var editSummaryAnonymous: String
        public var oresDamagingPrefix: String
        public var oresGoodFaithPrefix: String
        public let htmlStripped: ((String) -> String)

        public init(title: String, searchPlaceholder: String, filter: String, emptyTitle: String, emptySubtitle: String, editSummaryAnonymous: String, oresDamagingPrefix: String, oresGoodFaithPrefix: String, htmlStripped: @escaping ((String) -> String)) {
            self.title = title
            self.searchPlaceholder = searchPlaceholder
            self.filter = filter
            self.emptyTitle = emptyTitle
            self.emptySubtitle = emptySubtitle
            self.editSummaryAnonymous = editSummaryAnonymous
            self.oresDamagingPrefix = oresDamagingPrefix
            self.oresGoodFaithPrefix = oresGoodFaithPrefix
            self.htmlStripped = htmlStripped
        }
    }

    // MARK: - Item view model

    public struct ItemViewModel: Identifiable {
        public let id: UInt
        public let title: String
        public let commentHTML: String
        public let timestamp: Date
        public let username: String
        public let isAnonymous: Bool
        public let isBot: Bool
        public let isMinor: Bool
        public let revisionID: UInt
        public let oldRevisionID: UInt
        public let rcid: UInt
        public let byteChange: Int
        public let tags: [String]
        public let oresDamaging: Float?
        public let oresGoodFaith: Float?
        public let project: WMFProject
        private let htmlStripped: ((String) -> String)

        init(item: WMFRecentEdits.Item, htmlStripped: @escaping ((String) -> String)) {
            self.id = item.id
            self.title = item.title
            self.commentHTML = item.parsedComment
            self.timestamp = item.timestamp
            self.username = item.username
            self.isAnonymous = item.isAnon
            self.isBot = item.isBot
            self.isMinor = item.isMinor
            self.revisionID = item.revisionID
            self.oldRevisionID = item.oldRevisionID
            self.rcid = item.rcid
            self.byteChange = item.byteLength - item.oldByteLength
            self.tags = item.tags
            self.oresDamaging = item.oresDamaging
            self.oresGoodFaith = item.oresGoodFaith
            self.project = item.project
            self.htmlStripped = htmlStripped
        }

        public var comment: String { htmlStripped(commentHTML) }

        public var joinedTags: String { tags.joined(separator: ", ") }

        /// Whether an ORES quality/intent cue can be shown for this row.
        public var hasORESScores: Bool { oresDamaging != nil || oresGoodFaith != nil }

        /// Local-search match, mirroring Android's `pagingData.filter { ... }`.
        func matches(query: String) -> Bool {
            guard !query.isEmpty else { return true }
            let q = query.lowercased()
            return comment.lowercased().contains(q)
                || title.lowercased().contains(q)
                || username.lowercased().contains(q)
                || joinedTags.lowercased().contains(q)
        }
    }

    // MARK: - Section view model (day bucket)

    public struct SectionViewModel: Identifiable {
        public let id = UUID()
        public let date: Date
        public let items: [ItemViewModel]

        public var title: String {
            SectionViewModel.dateFormatter.string(from: date)
        }

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .none
            return formatter
        }()
    }

    // MARK: - Properties

    public var localizedStrings: LocalizedStrings
    public let project: WMFProject
    public weak var delegate: WMFRecentEditsDelegate?

    private let dataController: WMFRecentEditsDataController
    private var allItems: [ItemViewModel] = []
    private var continueString: String?

    @Published public var sections: [SectionViewModel] = []
    @Published public var activeFilterCount: Int = 0
    @Published public var hasPerformedInitialFetch = false
    @Published public var isLoading = false
    @Published public var currentQuery: String = "" {
        didSet { rebuildSections() }
    }

    // MARK: - Lifecycle

    public init(project: WMFProject, localizedStrings: LocalizedStrings, dataController: WMFRecentEditsDataController = .shared, delegate: WMFRecentEditsDelegate? = nil) {
        self.project = project
        self.localizedStrings = localizedStrings
        self.dataController = dataController
        self.delegate = delegate
        self.activeFilterCount = dataController.activeFilterCount()
    }

    // MARK: - Fetch

    public func fetchRecentEdits(_ completion: (() -> Void)? = nil) {
        guard !isLoading else { completion?(); return }
        isLoading = true
        allItems = []
        continueString = nil

        dataController.fetchRecentEdits(project: project) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let recentEdits):
                    self.allItems = recentEdits.items.map { ItemViewModel(item: $0, htmlStripped: self.localizedStrings.htmlStripped) }
                    self.continueString = recentEdits.continueString
                    self.activeFilterCount = recentEdits.activeFilterCount
                    self.rebuildSections()
                case .failure:
                    break
                }
                self.hasPerformedInitialFetch = true
                self.isLoading = false
                completion?()
            }
        }
    }

    /// Loads the next page (timestamp cursor + continuation), appending to the feed.
    /// The client-side ORES/experience filters can shrink a page to a few or zero rows,
    /// so the app calls this until enough rows are visible or the feed ends.
    public func loadMoreIfNeeded(_ completion: (() -> Void)? = nil) {
        guard !isLoading else { completion?(); return }
        let cursor = allItems.last?.timestamp ?? Date()
        isLoading = true

        dataController.fetchRecentEdits(project: project, startTimestamp: cursor, direction: "older", continueString: continueString) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                if case .success(let recentEdits) = result {
                    let newItems = recentEdits.items.map { ItemViewModel(item: $0, htmlStripped: self.localizedStrings.htmlStripped) }
                    // Avoid duplicates across pages.
                    let existingIDs = Set(self.allItems.map { $0.id })
                    self.allItems.append(contentsOf: newItems.filter { !existingIDs.contains($0.id) })
                    self.continueString = recentEdits.continueString
                    self.rebuildSections()
                }
                self.isLoading = false
                completion?()
            }
        }
    }

    public func refreshActiveFilterCount() {
        activeFilterCount = dataController.activeFilterCount()
    }

    public var isEmpty: Bool {
        hasPerformedInitialFetch && sections.isEmpty
    }

    // MARK: - Interactions

    public func didTapItem(_ item: ItemViewModel) {
        let flat = flattenedItems()
        let index = flat.firstIndex(where: { $0.id == item.id }) ?? 0
        delegate?.recentEditsDidTapItem(item, allItems: flat, index: index)
    }

    public func didTapFilter() {
        delegate?.recentEditsDidTapFilter()
    }

    public func didTapUser(_ item: ItemViewModel) {
        delegate?.recentEditsDidTapUser(username: item.username, project: item.project)
    }

    // MARK: - Sectioning + search

    private func flattenedItems() -> [ItemViewModel] {
        sections.flatMap { $0.items }
    }

    private func rebuildSections() {
        let filtered = allItems.filter { $0.matches(query: currentQuery) }
        sections = Self.dayBucketed(filtered)
    }

    /// Sort items into "day" buckets, descending by date (parity with Android's
    /// `insertSeparators` day grouping and the Watchlist feed).
    static func dayBucketed(_ items: [ItemViewModel]) -> [SectionViewModel] {
        let calendar = Calendar.current
        var dictionary: [Date: [ItemViewModel]] = [:]

        for item in items {
            let day = calendar.startOfDay(for: item.timestamp)
            dictionary[day, default: []].append(item)
        }

        return dictionary.keys.sorted(by: >).map { date in
            let sorted = (dictionary[date] ?? []).sorted { $0.timestamp > $1.timestamp }
            return SectionViewModel(date: date, items: sorted)
        }
    }
}
