import Foundation

/// Result of a recent-edits (Edit Patrol) fetch, parallel to `WMFWatchlist`.
public struct WMFRecentEdits: Sendable {

    public struct Item: Sendable, Identifiable, Equatable {
        public let title: String
        public let pageID: Int
        /// The current revision id (`revid`).
        public let revisionID: UInt
        /// The parent revision id (`old_revid`).
        public let oldRevisionID: UInt
        /// The recent-changes id (`rcid`).
        public let rcid: UInt
        public let username: String
        public let isAnon: Bool
        public let isBot: Bool
        public let isMinor: Bool
        public let isNew: Bool
        public let timestamp: Date
        public let parsedComment: String
        public let comment: String
        public let tags: [String]
        public let byteLength: Int
        public let oldByteLength: Int
        /// ORES `damaging.true` probability, when available on the wiki.
        public let oresDamaging: Float?
        /// ORES `goodfaith.true` probability, when available on the wiki.
        public let oresGoodFaith: Float?
        public let project: WMFProject

        public var id: UInt { rcid != 0 ? rcid : revisionID }

        public init(title: String, pageID: Int, revisionID: UInt, oldRevisionID: UInt, rcid: UInt, username: String, isAnon: Bool, isBot: Bool, isMinor: Bool, isNew: Bool, timestamp: Date, parsedComment: String, comment: String, tags: [String], byteLength: Int, oldByteLength: Int, oresDamaging: Float?, oresGoodFaith: Float?, project: WMFProject) {
            self.title = title
            self.pageID = pageID
            self.revisionID = revisionID
            self.oldRevisionID = oldRevisionID
            self.rcid = rcid
            self.username = username
            self.isAnon = isAnon
            self.isBot = isBot
            self.isMinor = isMinor
            self.isNew = isNew
            self.timestamp = timestamp
            self.parsedComment = parsedComment
            self.comment = comment
            self.tags = tags
            self.byteLength = byteLength
            self.oldByteLength = oldByteLength
            self.oresDamaging = oresDamaging
            self.oresGoodFaith = oresGoodFaith
            self.project = project
        }

        /// The joined tag string used for local search, mirroring Android's `joinedTags`.
        public var joinedTags: String {
            tags.joined(separator: ", ")
        }
    }

    /// The client-filtered, timestamp-descending list of edits shown in the feed.
    public let items: [Item]
    /// The full, unfiltered list from the server page. Used by the revert-candidate
    /// cache to track the newest revision id / timestamp (mirrors Android's second
    /// element of the `Triple`).
    public let unfilteredItems: [Item]
    /// Continuation token (`rccontinue`) for the next page, if any.
    public let continueString: String?
    public let activeFilterCount: Int

    public init(items: [Item], unfilteredItems: [Item], continueString: String?, activeFilterCount: Int) {
        self.items = items
        self.unfilteredItems = unfilteredItems
        self.continueString = continueString
        self.activeFilterCount = activeFilterCount
    }
}

/// Result of the patrol-eligibility check (home-wiki userinfo), mirroring
/// `SuggestedEditsTasksFragmentViewModel.allowToPatrolEdits`.
public struct WMFPatrolEligibility: Sendable, Equatable {
    public let isEligible: Bool
    public let isBlocked: Bool
    public let editCount: Int
    public let hasRollbackRights: Bool
    public let isSysop: Bool

    public init(isEligible: Bool, isBlocked: Bool, editCount: Int, hasRollbackRights: Bool, isSysop: Bool) {
        self.isEligible = isEligible
        self.isBlocked = isBlocked
        self.editCount = editCount
        self.hasRollbackRights = hasRollbackRights
        self.isSysop = isSysop
    }
}
