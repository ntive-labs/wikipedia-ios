import UIKit
import SwiftUI
import WMFData

fileprivate final class WMFCommonsCaptionEditHostingController: WMFComponentHostingController<WMFCommonsCaptionEditView> {
    init(viewModel: WMFCommonsCaptionEditViewModel) {
        super.init(rootView: WMFCommonsCaptionEditView(viewModel: viewModel))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Hosting controller for the Commons caption editor.
public final class WMFCommonsCaptionEditViewController: WMFCanvasViewController, WMFNavigationBarConfiguring {

    private let hostingViewController: WMFCommonsCaptionEditHostingController
    private let viewModel: WMFCommonsCaptionEditViewModel

    public init(viewModel: WMFCommonsCaptionEditViewModel) {
        self.viewModel = viewModel
        self.hostingViewController = WMFCommonsCaptionEditHostingController(viewModel: viewModel)
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
}
