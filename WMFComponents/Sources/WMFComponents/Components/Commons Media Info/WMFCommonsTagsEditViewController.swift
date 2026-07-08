import UIKit
import WMFData

/// Editor for adding structured "depicts" (P180) tags to a Commons file.
///
/// Mirrors Android's `SuggestedEditsImageTagsFragment`: an image preview, a set of selected-tag
/// chips, an "add tag" affordance that opens a Wikidata item search sheet, a CC0 licensing notice,
/// and a publish button. Closing with unpublished tags shows an exit-guard confirmation.
public final class WMFCommonsTagsEditViewController: WMFComponentViewController, WMFNavigationBarConfiguring {

    // MARK: - Properties

    private let viewModel: WMFCommonsTagsEditViewModel

    public var didTapClose: (() -> Void)?

    // MARK: - Subviews

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
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

    /// Vertical container holding one removable pill row per selected tag.
    private lazy var chipsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        return stackView
    }()

    private lazy var addTagButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = WMFFont.for(.headline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = "commons-tags-edit-add-button"
        button.addTarget(self, action: #selector(didTapAddTag), for: .touchUpInside)
        return button
    }()

    private lazy var cc0Label: UILabel = {
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
        button.accessibilityIdentifier = "commons-tags-edit-publish-button"
        button.heightAnchor.constraint(equalToConstant: 46).isActive = true
        button.addTarget(self, action: #selector(didTapPublish), for: .touchUpInside)
        return button
    }()

    // MARK: - Lifecycle

    public init(viewModel: WMFCommonsTagsEditViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupSubviews()
        configureStaticContent()
        loadThumbnailIfNeeded()
        viewModel.onSelectedTagsChanged = { [weak self] in
            self?.rebuildChips()
            self?.updateControlState()
        }
        rebuildChips()
        updateColors()
        updateControlState()
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

        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(divider)
        stackView.addArrangedSubview(chipsStackView)
        stackView.addArrangedSubview(addTagButton)
        stackView.addArrangedSubview(cc0Label)
        stackView.addArrangedSubview(publishButton)
        stackView.setCustomSpacing(24, after: cc0Label)

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

            imageView.heightAnchor.constraint(equalToConstant: 180)
        ])
    }

    private func configureStaticContent() {
        subtitleLabel.text = viewModel.subtitle
        addTagButton.setTitle(viewModel.localizedStrings.addTagButtonTitle, for: .normal)
        cc0Label.text = viewModel.localizedStrings.cc0NoticeText
        publishButton.setTitle(viewModel.localizedStrings.publishButtonTitle, for: .normal)
    }

    private func configureNavigationBar() {
        let titleConfig = WMFNavigationBarTitleConfig(title: viewModel.localizedStrings.title, customView: nil, alignment: .centerCompact)
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

    // MARK: - Chips

    private func rebuildChips() {
        chipsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for tag in viewModel.selectedTags {
            chipsStackView.addArrangedSubview(makeChip(for: tag))
        }
        chipsStackView.isHidden = viewModel.selectedTags.isEmpty
    }

    private func makeChip(for tag: WMFDepictsTag) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = theme.accent
        container.layer.cornerRadius = 16
        container.clipsToBounds = true

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = tag.label
        label.font = WMFFont.for(.subheadline)
        label.textColor = theme.paperBackground

        let removeButton = UIButton(type: .system)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.setImage(WMFSFSymbolIcon.for(symbol: .close), for: .normal)
        removeButton.tintColor = theme.paperBackground
        removeButton.accessibilityLabel = "Remove \(tag.label)"
        let capturedTag = tag
        removeButton.addAction(UIAction { [weak self] _ in
            self?.viewModel.removeTag(capturedTag)
        }, for: .touchUpInside)

        container.addSubview(label)
        container.addSubview(removeButton)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 32),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            removeButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
            removeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            removeButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 18)
        ])
        return container
    }

    // MARK: - Theming

    private func updateColors() {
        view.backgroundColor = theme.midBackground
        subtitleLabel.textColor = theme.secondaryText
        divider.backgroundColor = theme.border
        addTagButton.setTitleColor(theme.link, for: .normal)
        cc0Label.textColor = theme.secondaryText
        publishButton.setTitleColor(theme.paperBackground, for: .normal)
        rebuildChips()
        updateControlState()
    }

    // MARK: - State

    private func updateControlState() {
        let canPublish = viewModel.canPublish
        publishButton.isEnabled = canPublish
        publishButton.backgroundColor = canPublish ? theme.link : theme.secondaryText
    }

    // MARK: - Actions

    @objc private func didTapAddTag() {
        let searchVC = WMFCommonsTagSearchViewController(
            title: viewModel.localizedStrings.searchTitle,
            placeholder: viewModel.localizedStrings.searchPlaceholder,
            performSearch: { [weak self] term in
                guard let self else { return [] }
                return await self.viewModel.search(term: term)
            },
            isAlreadySelected: { [weak self] tag in
                self?.viewModel.isSelected(tag) ?? false
            },
            onSelect: { [weak self] tag in
                self?.viewModel.addTag(tag)
            })
        searchVC.didTapClose = { [weak searchVC] in
            searchVC?.dismiss(animated: true)
        }
        let navigationController = WMFComponentNavigationController(rootViewController: searchVC, modalPresentationStyle: .pageSheet)
        present(navigationController, animated: true)
    }

    @objc private func didTapPublish() {
        guard viewModel.canPublish else { return }
        publishButton.isEnabled = false
        viewModel.publish()
    }

    @objc private func didTapCloseButton() {
        guard viewModel.hasUnpublishedTags else {
            didTapClose?()
            return
        }
        let alert = UIAlertController(title: viewModel.localizedStrings.exitConfirmationTitle, message: viewModel.localizedStrings.exitConfirmationMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: viewModel.localizedStrings.exitConfirmationKeepEditing, style: .cancel))
        alert.addAction(UIAlertAction(title: viewModel.localizedStrings.exitConfirmationDiscard, style: .destructive) { [weak self] _ in
            self?.didTapClose?()
        })
        present(alert, animated: true)
    }

    /// Re-enables the publish button after a failed publish so the user can retry.
    public func handlePublishFailure() {
        updateControlState()
    }
}
