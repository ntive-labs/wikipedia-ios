import Foundation

// MARK: - imageinfo | entityterms

/// Response for `action=query&prop=imageinfo|entityterms` (formatversion=2).
/// Parity: Android `getImageInfoWithEntityTerms` → `MwQueryResponse`.
struct WMFCommonsImageInfoResponse: Decodable {

    struct Query: Decodable {
        let pages: [Page]?
    }

    struct Page: Decodable {
        let pageid: Int?
        let title: String?
        let imagerepository: String?
        let imageinfo: [ImageInfo]?
        let entityterms: EntityTerms?

        /// Parity: Android `MwQueryPage.isImageShared` == (imagerepository == "shared").
        var isImageShared: Bool {
            return (imagerepository ?? "") == "shared"
        }
    }

    struct EntityTerms: Decodable {
        let label: [String]?
        let description: [String]?
    }

    struct ImageInfo: Decodable {
        let thumburl: String?
        let thumbwidth: Int?
        let thumbheight: Int?
        let url: String?
        let descriptionurl: String?
        let mime: String?
        let user: String?
        let timestamp: String?
        let extmetadata: ExtMetadata?
    }

    struct ExtMetadata: Decodable {
        let artist: MetadataValue?
        let dateTime: MetadataValue?
        let credit: MetadataValue?
        let licenseShortName: MetadataValue?
        let licenseUrl: MetadataValue?

        enum CodingKeys: String, CodingKey {
            case artist = "Artist"
            case dateTime = "DateTime"
            case credit = "Credit"
            case licenseShortName = "LicenseShortName"
            case licenseUrl = "LicenseUrl"
        }
    }

    struct MetadataValue: Decodable {
        let value: String?
    }

    let query: Query?
}

// MARK: - protection | userinfo

/// Response for `action=query&meta=userinfo&prop=info&inprop=protection&uiprop=groups`.
/// Parity: Android `getProtectionWithUserInfo` → `MwQueryResult.isEditProtected`.
struct WMFCommonsProtectionResponse: Decodable {

    struct Query: Decodable {
        let pages: [Page]?
        let userinfo: UserInfo?
    }

    struct Page: Decodable {
        let protection: [Protection]?
    }

    struct Protection: Decodable {
        let type: String?
        let level: String?
        let expiry: String?
    }

    struct UserInfo: Decodable {
        let groups: [String]?
    }

    let query: Query?

    /// Parity: Android `MwQueryResult.isEditProtected` — an "edit" protection whose level is not in
    /// the current user's groups means the file is edit-protected for this user.
    var isEditProtected: Bool {
        guard let page = query?.pages?.first, let protections = page.protection else {
            return false
        }
        let groups = query?.userinfo?.groups ?? []
        for protection in protections {
            if protection.type == "edit", let level = protection.level, !groups.contains(level) {
                return true
            }
        }
        return false
    }
}

// MARK: - wbgetclaims (P180 depicts)

/// Response for `action=wbgetclaims&entity=M<pageID>&property=P180`.
/// Parity: Android `getClaims` → `Claims`.
struct WMFCommonsClaimsResponse: Decodable {

    struct Claim: Decodable {
        let mainsnak: MainSnak?
    }

    struct MainSnak: Decodable {
        let datavalue: DataValue?
    }

    struct DataValue: Decodable {
        let value: EntityValue?
    }

    struct EntityValue: Decodable {
        let id: String?
    }

    let claims: [String: [Claim]]?

    /// The list of Wikidata Q-ids referenced by the P180 statements.
    /// Parity: Android `ImageTagsProvider.getDepictsClaims`.
    var depictsItemIDs: [String] {
        return (claims?["P180"] ?? []).compactMap { $0.mainsnak?.datavalue?.value?.id }
    }
}

// MARK: - Wikidata entityterms labels

/// Response for `action=query&prop=entityterms&titles=<Q-ids>&wbetlanguage=<lang>` on Wikidata.
/// Parity: Android `getWikidataEntityTerms`.
struct WMFWikidataEntityTermsResponse: Decodable {

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

// MARK: - wbsearchentities

/// Response for `action=wbsearchentities&type=item`.
/// Parity: Android `searchEntities` → `Search`.
struct WMFWikidataSearchResponse: Decodable {

    struct SearchResult: Decodable {
        let id: String?
        let label: String?
        let description: String?
    }

    let search: [SearchResult]?
}
