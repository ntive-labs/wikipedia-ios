import Foundation

// MARK: - Shared decodables for Commons MediaInfo API responses (formatversion=2)

extension WMFCommonsMediaInfoDataController {

    /// A MediaWiki `extmetadata` value. The underlying JSON `value` can be a string, number, or bool,
    /// so we decode leniently and expose a normalized `stringValue`.
    struct ExtMetadataValue: Decodable {
        let stringValue: String?

        private enum CodingKeys: String, CodingKey { case value }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let string = try? container.decode(String.self, forKey: .value) {
                stringValue = string
            } else if let int = try? container.decode(Int.self, forKey: .value) {
                stringValue = String(int)
            } else if let double = try? container.decode(Double.self, forKey: .value) {
                stringValue = String(double)
            } else if let bool = try? container.decode(Bool.self, forKey: .value) {
                stringValue = String(bool)
            } else {
                stringValue = nil
            }
        }
    }

    // MARK: wbgetentities (captions)

    struct EntitiesResponse: Decodable {
        struct Entity: Decodable {
            struct Label: Decodable {
                let language: String
                let value: String
            }
            let labels: [String: Label]?
            let lastrevid: Int?
        }
        let entities: [String: Entity]?
    }

    struct CaptionPublishResponse: Decodable {
        struct Entity: Decodable {
            let lastrevid: Int?
        }
        let entity: Entity?
        let success: Int?
    }

    // MARK: query prop=imageinfo|entityterms

    struct ImageInfoResponse: Decodable {
        struct Query: Decodable {
            let pages: [Page]?
            var firstPage: Page? { pages?.first }
        }
        struct Page: Decodable {
            let pageid: Int?
            let title: String?
            let imagerepository: String?
            let imageinfo: [ImageInfo]?
            let entityterms: EntityTerms?

            /// Android parity: `MwQueryPage.isImageShared` == `imagerepository == "shared"`.
            var isImageShared: Bool { (imagerepository ?? "") == "shared" }
        }
        struct ImageInfo: Decodable {
            let timestamp: String?
            let user: String?
            let thumburl: String?
            let thumbwidth: Int?
            let thumbheight: Int?
            let url: String?
            let descriptionurl: String?
            let mime: String?
            let extmetadata: [String: ExtMetadataValue]?
        }
        struct EntityTerms: Decodable {
            let label: [String]?
        }
        let query: Query?
    }

    // MARK: query meta=userinfo prop=info inprop=protection

    struct ProtectionResponse: Decodable {
        struct Query: Decodable {
            let pages: [Page]?
            let userinfo: UserInfo?
            var firstPage: Page? { pages?.first }
        }
        struct Page: Decodable {
            let protection: [Protection]?
        }
        struct Protection: Decodable {
            let type: String
            let level: String
            let expiry: String?
        }
        struct UserInfo: Decodable {
            let groups: [String]?
        }
        let query: Query?
    }

    // MARK: wbgetclaims (P180 depicts)

    struct ClaimsResponse: Decodable {
        struct Claim: Decodable {
            let mainsnak: MainSnak?
        }
        struct MainSnak: Decodable {
            let datavalue: DataValue?
        }
        struct DataValue: Decodable {
            /// Only the wikibase-entityid shape (`{ "value": { "id": "Q..." } }`) is relevant for P180.
            let value: EntityIDValue?
            let type: String?
            var entityID: String? { value?.id }
        }
        struct EntityIDValue: Decodable {
            let id: String?
        }
        let claims: [String: [Claim]]?
    }

    // MARK: query prop=entityterms (Wikidata label resolution)

    struct EntityTermsResponse: Decodable {
        struct Query: Decodable {
            let pages: [Page]?
        }
        struct Page: Decodable {
            let title: String?
            let entityterms: EntityTerms?
        }
        struct EntityTerms: Decodable {
            let label: [String]?
            let description: [String]?
        }
        let query: Query?
    }
}
