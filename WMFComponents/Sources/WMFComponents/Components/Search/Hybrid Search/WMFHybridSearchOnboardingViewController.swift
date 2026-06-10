import SwiftUI

/// UIKit hosting controller for `WMFHybridSearchOnboardingView`, so legacy UIKit code can present the hybrid search onboarding modally.
public final class WMFHybridSearchOnboardingViewController: WMFCanvasViewController {

    // MARK: - Properties

    private let hostingController: WMFComponentHostingController<WMFHybridSearchOnboardingView>

    // MARK: - Lifecycle

    public init(viewModel: WMFHybridSearchOnboardingViewModel) {
        self.hostingController = WMFComponentHostingController(rootView: WMFHybridSearchOnboardingView(viewModel: viewModel))
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        addComponent(hostingController, pinToEdges: true)
    }
}
