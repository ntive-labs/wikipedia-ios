import UIKit
import SwiftUI
import WMFData

/// Hosting controller for the Edit Patrol feed. Wraps `WMFRecentEditsView` and adds a
/// filter bar button whose title reflects the active filter count (parity with the
/// Watchlist / Android patrol feed toolbars).
public final class WMFRecentEditsHostingController: WMFComponentHostingController<WMFRecentEditsView> {

    private let viewModel: WMFRecentEditsViewModel

    public init(viewModel: WMFRecentEditsViewModel) {
        self.viewModel = viewModel
        super.init(rootView: WMFRecentEditsView(viewModel: viewModel))
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.localizedStrings.title
        configureFilterButton()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.refreshActiveFilterCount()
        configureFilterButton()
    }

    /// Call after the filter screen is dismissed to refresh the feed + badge.
    public func filtersDidChange() {
        viewModel.refreshActiveFilterCount()
        configureFilterButton()
        viewModel.fetchRecentEdits()
    }

    private func configureFilterButton() {
        let count = viewModel.activeFilterCount
        let title = count > 0 ? "\(viewModel.localizedStrings.filter) (\(count))" : viewModel.localizedStrings.filter
        let button = UIBarButtonItem(title: title, style: .plain, target: self, action: #selector(didTapFilter))
        button.accessibilityIdentifier = "edit-patrol-filter-button"
        navigationItem.rightBarButtonItem = button
    }

    @objc private func didTapFilter() {
        viewModel.didTapFilter()
    }
}
