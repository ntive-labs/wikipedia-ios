import Foundation
import WMFData

/// View model for the Commons depicts (P180 image tags) editor — iOS analogue of Android's
/// `SuggestedEditsImageTagsFragment` + `SuggestedEditsImageTagDialog` + `publishImageTags`.
@MainActor
public final class WMFCommonsDepictsEditViewModel: ObservableObject {

    public enum State: Equatable {
        case editing
        case publishing
        case published
        case error
    }

    public struct LocalizedStrings: Sendable {
        public let title: String
        public let instructions: String
        public let searchPlaceholder: String
        public let cc0Notice: String
        public let publishButtonTitle: String
        public let publishingButtonTitle: String
        public let exitConfirmationTitle: String
        public let exitConfirmationMessage: String
        public let exitConfirmationDiscard: String
        public let exitConfirmationKeepEditing: String
        public let errorTitle: String

        public init(title: String, instructions: String, searchPlaceholder: String, cc0Notice: String, publishButtonTitle: String, publishingButtonTitle: String, exitConfirmationTitle: String, exitConfirmationMessage: String, exitConfirmationDiscard: String, exitConfirmationKeepEditing: String, errorTitle: String) {
            self.title = title
            self.instructions = instructions
            self.searchPlaceholder = searchPlaceholder
            self.cc0Notice = cc0Notice
            self.publishButtonTitle = publishButtonTitle
            self.publishingButtonTitle = publishingButtonTitle
            self.exitConfirmationTitle = exitConfirmationTitle
            self.exitConfirmationMessage = exitConfirmationMessage
            self.exitConfirmationDiscard = exitConfirmationDiscard
            self.exitConfirmationKeepEditing = exitConfirmationKeepEditing
            self.errorTitle = errorTitle
        }
    }

    // MARK: - Inputs

    public let localizedStrings: LocalizedStrings
    public let commonsTitle: String
    public let pageID: Int
    public let languageCode: String

    public var didPublishSuccessfully: (() -> Void)?

    // MARK: - Published state

    @Published public var searchTerm: String = ""
    @Published public private(set) var searchResults: [WMFDepictsTag] = []
    @Published public private(set) var selectedTags: [WMFDepictsTag] = []
    @Published public private(set) var state: State = .editing
    @Published public private(set) var errorMessage: String?

    // MARK: - Private

    private let dataController: WMFCommonsMediaInfoDataController
    private let searchController: WMFWikidataItemSearchDataController
    private var searchTask: Task<Void, Never>?

    public init(
        localizedStrings: LocalizedStrings,
        commonsTitle: String,
        pageID: Int,
        languageCode: String,
        dataController: WMFCommonsMediaInfoDataController = WMFCommonsMediaInfoDataController(),
        searchController: WMFWikidataItemSearchDataController = WMFWikidataItemSearchDataController()
    ) {
        self.localizedStrings = localizedStrings
        self.commonsTitle = commonsTitle
        self.pageID = pageID
        self.languageCode = languageCode
        self.dataController = dataController
        self.searchController = searchController
    }

    deinit {
        searchTask?.cancel()
    }

    // MARK: - Derived

    /// Parity: Android shows an exit-guard dialog when there are unpublished selected tags.
    public var hasUnpublishedSelections: Bool {
        !selectedTags.isEmpty && state != .published
    }

    public var canPublish: Bool {
        !selectedTags.isEmpty && state != .publishing
    }

    // MARK: - Search

    public func performSearch() {
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        guard !term.isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task { [weak self] in
            guard let self else { return }
            let results = (try? await self.searchController.search(term: term, languageCode: self.languageCode)) ?? []
            if Task.isCancelled { return }
            // Hide already-selected items from the result list.
            let selectedIDs = Set(self.selectedTags.map { $0.wikidataID })
            self.searchResults = results.filter { !selectedIDs.contains($0.wikidataID) }
        }
    }

    // MARK: - Selection

    public func selectTag(_ tag: WMFDepictsTag) {
        guard !selectedTags.contains(where: { $0.wikidataID == tag.wikidataID }) else { return }
        var selected = tag
        selected.isSelected = true
        selectedTags.append(selected)
        searchResults.removeAll { $0.wikidataID == tag.wikidataID }
        searchTerm = ""
        searchResults = []
    }

    public func removeTag(_ tag: WMFDepictsTag) {
        selectedTags.removeAll { $0.wikidataID == tag.wikidataID }
    }

    // MARK: - Publish

    public func publish() {
        guard !selectedTags.isEmpty else { return }
        state = .publishing
        errorMessage = nil
        let tags = selectedTags
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.dataController.publishDepicts(pageID: self.pageID, tags: tags)
                self.state = .published
                self.didPublishSuccessfully?()
            } catch {
                self.errorMessage = (error as NSError).localizedDescription
                self.state = .error
            }
        }
    }
}
