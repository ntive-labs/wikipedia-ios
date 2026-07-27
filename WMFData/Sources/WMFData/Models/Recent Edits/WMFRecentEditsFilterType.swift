import Foundation

/// Recent-edits (Edit Patrol) filter buckets, ported 1:1 from Android's
/// `SuggestedEditsRecentEditsFilterTypes.kt`.
///
/// Each case's `rawValue` matches the Android `id` string so that persisted
/// settings stay compatible with the parity contract. The `value` accessor
/// returns the API/score value used when building the `recentchanges` request
/// (server-side) or when applying on-device ORES / user-experience filters
/// (client-side).
public enum WMFRecentEditsFilterType: String, Codable, CaseIterable, Sendable {

    // Significance (single-select group)
    case allEdits = "allEdits"
    case minorEdits = "minorEdits"
    case nonMinorEdits = "nonMinorEdits"

    // Automated contributions (single-select group)
    case allEditors = "allEditors"
    case bot = "bot"
    case human = "human"

    // Latest revisions (single-select group)
    case latestRevision = "latestRevision"
    case notLatestRevision = "notLatestRevision"

    // User registration (multi-select)
    case unregistered = "unregistered"
    case registered = "registered"

    // User experience (multi-select) — "minEdits,maxEdits|minDays,maxDays" (-1 = unbounded)
    case newcomers = "newcomers"
    case learners = "learners"
    case experiencedUsers = "experiencedUsers"

    // Contribution quality — ORES damaging score buckets "min|max" (inclusive)
    case damagingGood = "damagingGood"
    case damagingMayProblems = "damagingMayProblems"
    case damagingLikelyProblems = "damagingLikelyProblems"
    case damagingBad = "damagingBad"

    // User intent — ORES good-faith score buckets "min|max" (inclusive)
    case goodfaithGood = "goodfaithGood"
    case goodfaithMayProblems = "goodfaithMayProblems"
    case goodfaithLikelyProblems = "goodfaithLikelyProblems"
    case goodfaithBad = "goodfaithBad"

    /// The API value (server `rcshow`/`rctoponly`) or the score/experience range
    /// consumed by the on-device filters. Matches Android's `value` column verbatim.
    public var value: String {
        switch self {
        case .allEdits: return ""
        case .minorEdits: return "minor"
        case .nonMinorEdits: return "!minor"
        case .allEditors: return ""
        case .bot: return "bot"
        case .human: return "!bot"
        case .latestRevision: return ""
        case .notLatestRevision: return "1"
        case .unregistered: return "anon"
        case .registered: return "!anon"
        case .newcomers: return "0,10|0,4"
        case .learners: return "10,500|4,30"
        case .experiencedUsers: return "500,-1|30,-1"
        case .damagingGood: return "0|0.149"
        case .damagingMayProblems: return "0.149|0.629"
        case .damagingLikelyProblems: return "0.629|0.944"
        case .damagingBad: return "0.944|1"
        case .goodfaithGood: return "0.75|1"
        case .goodfaithMayProblems: return "0.647|0.75"
        case .goodfaithLikelyProblems: return "0.25|0.647"
        case .goodfaithBad: return "0|0.25"
        }
    }

    /// The Android `id` string (identical to `rawValue`). Kept as a named accessor
    /// so the port reads the same as the Kotlin source.
    public var id: String { rawValue }

    // MARK: - Groups (mirror Android companion object)

    public static let minorEditsGroup: [WMFRecentEditsFilterType] = [.allEdits, .minorEdits, .nonMinorEdits]
    public static let botEditsGroup: [WMFRecentEditsFilterType] = [.allEditors, .bot, .human]
    public static let latestRevisionsGroup: [WMFRecentEditsFilterType] = [.latestRevision, .notLatestRevision]
    public static let userRegistrationGroup: [WMFRecentEditsFilterType] = [.unregistered, .registered]
    public static let userExperienceGroup: [WMFRecentEditsFilterType] = [.newcomers, .learners, .experiencedUsers]
    public static let damagingGroup: [WMFRecentEditsFilterType] = [.damagingGood, .damagingMayProblems, .damagingLikelyProblems, .damagingBad]
    public static let goodfaithGroup: [WMFRecentEditsFilterType] = [.goodfaithGood, .goodfaithMayProblems, .goodfaithLikelyProblems, .goodfaithBad]

    // MARK: - Defaults (mirror Android companion object)

    /// Multiple choice default (user status).
    public static let defaultFilterUserStatus: Set<WMFRecentEditsFilterType> = [.unregistered, .newcomers]

    /// Single choice defaults (significance / latest / automated).
    public static let defaultFilterOthers: Set<WMFRecentEditsFilterType> = [.allEdits, .latestRevision, .allEditors]

    /// The full default selection.
    public static let defaultFilterTypeSet: Set<WMFRecentEditsFilterType> = defaultFilterUserStatus.union(defaultFilterOthers)

    /// Mirrors Android `find(id)` — matches an exact id or a prefix, falling back to `.allEdits`.
    public static func find(id: String) -> WMFRecentEditsFilterType {
        return allCases.first(where: { id == $0.id || id.hasPrefix($0.id) }) ?? .allEdits
    }

    // MARK: - Score / experience parsing helpers

    /// Parsed ORES score range `(min, max)` for damaging/good-faith buckets.
    public var scoreRange: (min: Float, max: Float)? {
        let parts = value.split(separator: "|")
        guard parts.count == 2, let min = Float(parts[0]), let max = Float(parts[1]) else {
            return nil
        }
        return (min, max)
    }

    /// Parsed user-experience bounds `((minEdits, maxEdits), (minDays, maxDays))`, `-1` = unbounded.
    public var experienceRange: (edits: (min: Int, max: Int), days: (min: Int, max: Int))? {
        let halves = value.split(separator: "|")
        guard halves.count == 2 else { return nil }
        let editParts = halves[0].split(separator: ",")
        let dayParts = halves[1].split(separator: ",")
        guard editParts.count == 2, dayParts.count == 2,
              let minEdits = Int(editParts[0]), let maxEdits = Int(editParts[1]),
              let minDays = Int(dayParts[0]), let maxDays = Int(dayParts[1]) else {
            return nil
        }
        return ((minEdits, maxEdits), (minDays, maxDays))
    }
}
