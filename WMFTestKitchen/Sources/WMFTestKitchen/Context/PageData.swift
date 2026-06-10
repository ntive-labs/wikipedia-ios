import Foundation

/// Page context data fields.
///
/// PageData are dynamic context fields that change with every request. PageData is submitted
/// with the events for which the host app provides it (e.g. interactions with a specific article).
public struct PageData: Encodable {
    public var id: Int?
    public var title: String?
    public var namespaceId: Int?
    public var namespaceName: String?
    public var revisionId: Int64?
    public var wikidataItemQid: String?
    public var contentLanguage: String?

    public init(
        id: Int? = nil,
        title: String? = nil,
        namespaceId: Int? = nil,
        namespaceName: String? = nil,
        revisionId: Int64? = nil,
        wikidataItemQid: String? = nil,
        contentLanguage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.namespaceId = namespaceId
        self.namespaceName = namespaceName
        self.revisionId = revisionId
        self.wikidataItemQid = wikidataItemQid
        self.contentLanguage = contentLanguage
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case namespaceId = "namespace_id"
        case namespaceName = "namespace_name"
        case revisionId = "revision_id"
        case wikidataItemQid = "wikidata_qid"
        case contentLanguage = "content_language"
    }
}
