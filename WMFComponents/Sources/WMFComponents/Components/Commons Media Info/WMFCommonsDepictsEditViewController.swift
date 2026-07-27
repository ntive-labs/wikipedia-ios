import UIKit
import SwiftUI
import WMFData

fileprivate final class WMFCommonsDepictsEditHostingController: WMFComponentHostingController<WMFCommonsDepictsEditView> {
    init(viewModel: WMFCommonsDepictsEditViewModel) {
        super.init(rootView: WMFCommonsDepictsEditView(viewModel: viewModel))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Hosting controller for the Commons depicts (image tags) editor.
/// Presents an exit-guard confirmation when there are unpublished selected tags (parity: Android
/// `onBackPressed` dialog).
public final class WMFCommonsDepictsEditViewController: WMFCanvasViewController, WMFNavigationBarConfiguring {

    private let hostingViewController: WMFCommonsDepictsEditHostingController
    private let viewModel: WMFCommonsDepictsEditViewModel

    public init(viewModel: WMFCommonsDepictsEditViewModel) {
        self.viewModel = viewModel
        self.hostingViewController = WMFCommonsDepictsEditHostingController(viewModel: viewModel)
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        addComponent(hostingViewController, pinToEdges: true, respectSafeArea: true)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let titleConfig = WMFNavigationBarTitleConfig(title: viewModel.localizedStrings.title, customView: nil, alignment: .centerCompact)
        configureNavigationBar(titleConfig: titleConfig, closeButtonConfig: nil, profileButtonConfig: nil, tabsButtonConfig: nil, searchBarConfig: nil, hideNavigationBarOnScroll: false)
    }

    /// Present the exit-guard when the user attempts to leave with unpublished selections.
    /// Returns `true` when it is safe to dismiss immediately.
    public func confirmExitIfNeeded(dismissHandler: @escaping () -> Void) -> Bool {
        guard viewModel.hasUnpublishedSelections else {
            return true
        }

        let alert = UIAlertController(
            title: viewModel.localizedStrings.exitConfirmationTitle,
            message: viewModel.localizedStrings.exitConfirmationMessage,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: viewModel.localizedStrings.exitConfirmationKeepEditing, style: .cancel))
        alert.addAction(UIAlertAction(title: viewModel.localizedStrings.exitConfirmationDiscard, style: .destructive) { _ in
            dismissHandler()
        })
        present(alert, animated: true)
        return false
    }
}
