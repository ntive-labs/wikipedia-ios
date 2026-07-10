import Foundation
import CoreData
import WMF
import WMFData
import CocoaLumberjackSwift

/// Gathers local search matches — open tabs, reading history, and reading-list (saved) pages — to be
/// merged into standard article search results.
///
/// This mirrors Android's `StandardSearchRepository`, which prepends at most one match from each of
/// these three local sources (each scoped to the selected `WikiSite`) ahead of the remote prefix
/// results before de-duplicating (`StandardSearchRepository.kt:32–45`, `getSearchResultsFromTabs`,
/// `findHistoryItem`, `findPageForSearchQueryInAnyList`).
///
/// Main-actor isolated because it reads the app-side Core Data `viewContext`, which is main-thread only.
@MainActor
final class WMFLocalSearchProvider {

    private enum LocalArticleSource {
        case history
        case savedPage
    }

    /// Returns at most one match from each local source (open tab, reading history, saved page),
    /// each scoped to `siteURL`'s wiki and matching `term` (case- and diacritic-insensitive substring).
    /// Results are ordered tab → history → saved page, matching Android's source ordering.
    ///
    /// - Parameters:
    ///   - term: The current search term. Terms shorter than two non-whitespace characters return `[]`
    ///           (parity with Android's `searchTerm.length >= 2` guard).
    ///   - siteURL: The wiki the standard search is scoped to. Local matches from other wikis are excluded.
    ///   - dataStore: Provides the `viewContext` used for the history and saved-page lookups.
    func localResults(for term: String, siteURL: URL, dataStore: MWKDataStore) async -> [MWKSearchResult] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let tab = await tabResult(for: trimmed, siteURL: siteURL, dataStore: dataStore)
        let history = articleResult(for: trimmed, siteURL: siteURL, dataStore: dataStore, source: .history)
        let savedPage = articleResult(for: trimmed, siteURL: siteURL, dataStore: dataStore, source: .savedPage)

        return [tab, history, savedPage].compactMap { $0 }
    }

    // MARK: - Open tabs

    private func tabResult(for term: String, siteURL: URL, dataStore: MWKDataStore) async -> MWKSearchResult? {
        guard let tabs = try? await WMFArticleTabsDataController.shared.fetchAllArticleTabs() else {
            return nil
        }

        for tab in tabs {
            // `fetchAllArticleTabs()` stops appending at the current article, so the last entry is the
            // tab's visible article — the equivalent of Android's `tab.backStackPositionTitle`.
            guard let current = tab.articles.last,
                  let tabSiteURL = current.project.siteURL,
                  (tabSiteURL as NSURL).wmf_isEqual(toIgnoringScheme: siteURL) else {
                continue
            }

            let displayText = current.title.replacingOccurrences(of: "_", with: " ")
            guard displayText.localizedCaseInsensitiveContains(term) else { continue }

            // The tab data model carries no description/thumbnail, so enrich from the cached article
            // (present because the tab was viewed) to render a complete row. Fall back to the bare title.
            if let articleURL = current.articleURL,
               let article = cachedArticle(for: articleURL, dataStore: dataStore) {
                return makeSearchResult(
                    title: current.title,
                    displayTitle: article.displayTitle ?? displayText,
                    displayTitleHTML: article.displayTitleHTML,
                    wikidataDescription: article.capitalizedWikidataDescriptionOrSnippet,
                    thumbnailURL: article.imageURL(forWidth: ImageUtils.listThumbnailWidth())
                )
            }

            return makeSearchResult(
                title: current.title,
                displayTitle: displayText,
                displayTitleHTML: nil,
                wikidataDescription: current.description,
                thumbnailURL: current.imageURL
            )
        }

        return nil
    }

    /// Looks up the persisted `WMFArticle` for `url` without creating one, used to enrich tab results.
    private func cachedArticle(for url: URL, dataStore: MWKDataStore) -> WMFArticle? {
        guard let key = url.wmf_databaseKey else { return nil }
        let request: NSFetchRequest<WMFArticle> = WMFArticle.fetchRequest()
        request.predicate = NSPredicate(format: "key == %@", key)
        request.fetchLimit = 1
        return try? dataStore.viewContext.fetch(request).first
    }

    // MARK: - Reading history & saved pages

    private func articleResult(for term: String, siteURL: URL, dataStore: MWKDataStore, source: LocalArticleSource) -> MWKSearchResult? {
        let request: NSFetchRequest<WMFArticle> = WMFArticle.fetchRequest()

        let sourcePredicate: NSPredicate
        switch source {
        case .history:
            sourcePredicate = NSPredicate(format: "viewedDate != NULL")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \WMFArticle.viewedDate, ascending: false)]
        case .savedPage:
            sourcePredicate = NSPredicate(format: "savedDate != NULL")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \WMFArticle.savedDate, ascending: false)]
        }

        let titlePredicate = NSPredicate(format: "displayTitle CONTAINS[cd] %@", term)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [sourcePredicate, titlePredicate])
        // Fetch a small window and pick the first title on the requested wiki. The wiki filter runs
        // in-memory because `WMFArticle` has no site column, only a database key.
        request.fetchLimit = 20

        do {
            let articles = try dataStore.viewContext.fetch(request)
            for article in articles {
                guard let articleURL = article.url,
                      let articleSiteURL = articleURL.wmf_site,
                      (articleSiteURL as NSURL).wmf_isEqual(toIgnoringScheme: siteURL),
                      let title = articleURL.wmf_title else {
                    continue
                }

                return makeSearchResult(
                    title: title,
                    displayTitle: article.displayTitle ?? title,
                    displayTitleHTML: article.displayTitleHTML,
                    wikidataDescription: article.capitalizedWikidataDescriptionOrSnippet,
                    thumbnailURL: article.imageURL(forWidth: ImageUtils.listThumbnailWidth())
                )
            }
        } catch {
            DDLogError("WMFLocalSearchProvider failed to fetch \(source) results: \(error)")
        }

        return nil
    }

    // MARK: - Result construction

    private func makeSearchResult(title: String, displayTitle: String, displayTitleHTML: String?, wikidataDescription: String?, thumbnailURL: URL?) -> MWKSearchResult? {
        return MWKSearchResult(
            articleID: 0,
            revID: 0,
            title: title,
            displayTitle: displayTitle,
            displayTitleHTML: displayTitleHTML ?? displayTitle,
            wikidataDescription: wikidataDescription,
            extract: nil,
            thumbnailURL: thumbnailURL,
            index: nil,
            titleNamespace: NSNumber(value: 0),
            location: nil
        )
    }
}
