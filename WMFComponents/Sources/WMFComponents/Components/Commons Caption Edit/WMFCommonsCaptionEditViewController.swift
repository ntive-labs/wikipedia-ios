import UIKit
import WMFData

/// Editor for adding or translating a structured Commons image caption (MediaInfo label).
///
/// Visually mirrors the app's description-edit screen (subtitle, editable text, license/login
/// attribution, publish button) but writes a Commons caption via ``WMFCommonsMediaInfoDataController``
/// instead of a Wikidata/article description. Caption validation intentionally skips the article-only
/// "ends with punctuation" / capitalization rules.
public final class WMFCommonsCaptionEditViewController: WMFComponentViewController, WMFNavigationBarConfiguring {

    // MARK: - Properties

    private let viewModel: WMFCommonsCaptionEditViewModel

    /// When false, the login attribution line is hidden (permanent account users).
    private let showsLoginPrompt: Bool

    /// Invoked when the user taps the close button.
    public var didTapClose: (() -> Void)?

    // MARK: - Subviews

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        return scrollView
    }()

    private lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 16
        return stackView
    }()

    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.isHidden = true
        return imageView
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.font = WMFFont.for(.subheadline)
        return label
    }()

    private lazy var divider: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }()

    private lazy var textView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.font = WMFFont.for(.title3)
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.accessibilityIdentifier = "commons-caption-edit-text-view"
        textView.delegate = self
        textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return textView
    }()

    private lazy var placeholderLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.font = WMFFont.for(.title3)
        label.isUserInteractionEnabled = false
        return label
    }()

    private lazy var characterCountLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.adjustsFontForContentSizeCategory = true
        label.font = WMFFont.for(.footnote)
        label.textAlignment = .natural
        return label
    }()

    private lazy var lengthWarningLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.font = WMFFont.for(.footnote)
        label.isHidden = true
        return label
    }()

    private lazy var licenseLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.font = WMFFont.for(.caption1)
        return label
    }()

    private lazy var loginLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.font = WMFFont.for(.caption1)
        return label
    }()

    private lazy var publishButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = WMFFont.for(.semiboldHeadline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.layer.cornerRadius = 23
        button.clipsToBounds = true
        button.accessibilityIdentifier = "commons-caption-edit-publish-button"
        button.heightAnchor.constraint(equalToConstant: 46).isActive = true
        button.addTarget(self, action: #selector(didTapPublish), for: .touchUpInside)
        return button
    }()

    // MARK: - Lifecycle

    public init(viewModel: WMFCommonsCaptionEditViewModel, showsLoginPrompt: Bool) {
        self.viewModel = viewModel
        self.showsLoginPrompt = showsLoginPrompt
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupSubviews()
        characterCountLabel.textAlignment = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .left : .right
        configureStaticContent()
        loadThumbnailIfNeeded()
        updateColors()
        updateControlState()
        registerForKeyboardNotifications()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureNavigationBar()
    }

    public override func appEnvironmentDidChange() {
        super.appEnvironmentDidChange()
        updateColors()
    }

    // MARK: - Setup

    private func setupSubviews() {
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)

        let placeholderContainer = UIView()
        placeholderContainer.translatesAutoresizingMaskIntoConstraints = false
        placeholderContainer.addSubview(textView)
        placeholderContainer.addSubview(placeholderLabel)

        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(divider)
        stackView.addArrangedSubview(placeholderContainer)
        stackView.addArrangedSubview(characterCountLabel)
        stackView.addArrangedSubview(lengthWarningLabel)
        stackView.addArrangedSubview(licenseLabel)
        stackView.addArrangedSubview(loginLabel)
        stackView.addArrangedSubview(publishButton)

        stackView.setCustomSpacing(4, after: placeholderContainer)
        stackView.setCustomSpacing(24, after: lengthWarningLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),

            imageView.heightAnchor.constraint(equalToConstant: 180),

            textView.topAnchor.constraint(equalTo: placeholderContainer.topAnchor),
            textView.leadingAnchor.constraint(equalTo: placeholderContainer.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: placeholderContainer.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: placeholderContainer.bottomAnchor),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor)
        ])
    }

    private func configureStaticContent() {
        subtitleLabel.text = viewModel.subtitle
        placeholderLabel.text = viewModel.localizedStrings.placeholder
        licenseLabel.text = viewModel.localizedStrings.licenseText
        loginLabel.text = viewModel.localizedStrings.loginText
        loginLabel.isHidden = !showsLoginPrompt
        publishButton.setTitle(viewModel.localizedStrings.publishButtonTitle, for: .normal)
        lengthWarningLabel.text = viewModel.localizedStrings.lengthWarning

        if let existingCaption = viewModel.config.existingCaption, !existingCaption.isEmpty {
            textView.text = existingCaption
        }
        placeholderLabel.isHidden = !textView.text.isEmpty
        characterCountLabel.text = viewModel.characterCountText(for: textView.text)
    }

    private func configureNavigationBar() {
        let titleConfig = WMFNavigationBarTitleConfig(title: viewModel.navigationTitle, customView: nil, alignment: .centerCompact)
        let closeConfig = WMFLargeCloseButtonConfig(imageType: .plainX, target: self, action: #selector(didTapCloseButton), alignment: .leading)
        configureNavigationBar(titleConfig: titleConfig, closeButtonConfig: closeConfig, profileButtonConfig: nil, tabsButtonConfig: nil, searchBarConfig: nil, hideNavigationBarOnScroll: false)
    }

    private func loadThumbnailIfNeeded() {
        guard let url = viewModel.config.imageThumbnailURL else { return }
        WMFImageDataController.shared.fetchImageData(url: url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case .success(let data) = result, let image = UIImage(data: data) else { return }
                self.imageView.image = image
                self.imageView.isHidden = false
            }
        }
    }

    // MARK: - Theming

    private func updateColors() {
        view.backgroundColor = theme.midBackground
        subtitleLabel.textColor = theme.secondaryText
        divider.backgroundColor = theme.border
        textView.textColor = theme.text
        textView.keyboardAppearance = theme.keyboardAppearance
        placeholderLabel.textColor = theme.secondaryText
        licenseLabel.textColor = theme.secondaryText
        loginLabel.textColor = theme.secondaryText
        publishButton.setTitleColor(theme.paperBackground, for: .normal)
        updateControlState()
    }

    // MARK: - State

    private func updateControlState() {
        let isValid = viewModel.isValid(textView.text)
        publishButton.isEnabled = isValid
        publishButton.backgroundColor = isValid ? theme.link : theme.secondaryText

        let isOverLimit = viewModel.isOverLengthLimit(textView.text)
        lengthWarningLabel.isHidden = !isOverLimit
        lengthWarningLabel.textColor = theme.destructive
        characterCountLabel.text = viewModel.characterCountText(for: textView.text)
        characterCountLabel.textColor = isOverLimit ? theme.destructive : theme.secondaryText
        placeholderLabel.isHidden = !textView.text.isEmpty
    }

    // MARK: - Actions

    @objc private func didTapPublish() {
        guard viewModel.isValid(textView.text) else { return }
        view.endEditing(true)
        publishButton.isEnabled = false
        viewModel.publish(caption: textView.text)
    }

    @objc private func didTapCloseButton() {
        didTapClose?()
    }

    /// Re-enables the publish button after a failed publish so the user can retry.
    public func handlePublishFailure() {
        updateControlState()
    }

    // MARK: - Keyboard

    private func registerForKeyboardNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
        let keyboardFrame = view.convert(frameValue.cgRectValue, from: nil)
        let overlap = max(0, view.bounds.maxY - keyboardFrame.minY)
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }
}

// MARK: - UITextViewDelegate

extension WMFCommonsCaptionEditViewController: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        updateControlState()
    }
}
