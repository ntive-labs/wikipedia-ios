import UIKit
import SwiftUI
import WMFData

fileprivate final class WMFFileMediaInfoHostingController: WMFComponentHostingController<WMFFileMediaInfoView> {
    init(viewModel: WMFFileMediaInfoViewModel) {
        super.init(rootView: WMFFileMediaInfoView(viewModel: viewModel))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// The File Media Info screen host — iOS analogue of Android's `FilePageFragment` / `FilePageActivity`.
/// Owns the load → eligibility → CTA → refresh loop. `reloadMediaInfo()` is called by the coordinator
/// after a caption/tag edit publishes, so the CTA is replaced by the freshly added value in place.
public final class WMFFileMediaInfoViewController: WMFCanvasViewController, WMFNavigationBarConfiguring {

    private let hostingViewController: WMFFileMediaInfoHostingController
    private let viewModel: WMFFileMediaInfoViewModel

    public init(viewModel: WMFFileMediaInfoViewModel) {
        self.viewModel = viewModel
        self.hostingViewController = WMFFileMediaInfoHostingController(viewModel: viewModel)
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        addComponent(hostingViewController, pinToEdges: true, respectSafeArea: true)
        viewModel.loadMediaInfo()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureNavigationBar()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.loggingDelegate?.logFileMediaInfoDidAppear()
    }

    /// Re-fetches metadata in place (parity: Android calls `viewModel.loadImageInfo()` after a publish).
    public func reloadMediaInfo() {
        viewModel.loadMediaInfo()
    }

    private func configureNavigationBar() {
        let titleConfig = WMFNavigationBarTitleConfig(title: viewModel.localizedStrings.title, customView: nil, alignment: .centerCompact)
        configureNavigationBar(titleConfig: titleConfig, closeButtonConfig: nil, profileButtonConfig: nil, tabsButtonConfig: nil, searchBarConfig: nil, hideNavigationBarOnScroll: false)
    }
}
