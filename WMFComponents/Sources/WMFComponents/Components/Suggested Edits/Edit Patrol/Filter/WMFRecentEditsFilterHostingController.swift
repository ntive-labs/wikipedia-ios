import UIKit
import SwiftUI
import WMFData

/// Hosting controller for the Edit Patrol filter screen. Adds Reset / Done bar buttons
/// (parity with Android's filter activity reset action + toolbar).
public final class WMFRecentEditsFilterHostingController: WMFComponentHostingController<WMFRecentEditsFilterView> {

    private let viewModel: WMFRecentEditsFilterViewModel
    private let onDone: () -> Void

    public init(viewModel: WMFRecentEditsFilterViewModel, onDone: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDone = onDone
        super.init(rootView: WMFRecentEditsFilterView(viewModel: viewModel))
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.localizedStrings.title

        let reset = UIBarButtonItem(title: viewModel.localizedStrings.resetTitle, style: .plain, target: self, action: #selector(didTapReset))
        reset.accessibilityIdentifier = "edit-patrol-filter-reset"
        navigationItem.leftBarButtonItem = reset

        let done = UIBarButtonItem(title: viewModel.localizedStrings.doneTitle, style: .done, target: self, action: #selector(didTapDone))
        done.accessibilityIdentifier = "edit-patrol-filter-done"
        navigationItem.rightBarButtonItem = done
    }

    @objc private func didTapReset() {
        viewModel.reset()
    }

    @objc private func didTapDone() {
        onDone()
    }
}
