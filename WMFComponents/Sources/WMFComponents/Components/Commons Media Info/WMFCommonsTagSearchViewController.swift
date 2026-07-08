import UIKit
import WMFData

/// Search sheet for finding a Wikidata item to add as a "depicts" tag. Ports Android's
/// `SuggestedEditsImageTagDialog` (a search field over `wbsearchentities`, results in a list).
public final class WMFCommonsTagSearchViewController: WMFComponentViewController, WMFNavigationBarConfiguring, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Injected behaviour

    private let title_: String
    private let placeholder: String
    private let performSearch: (String) async -> [WMFDepictsTag]
    private let isAlreadySelected: (WMFDepictsTag) -> Bool
    private let onSelect: (WMFDepictsTag) -> Void

    // MARK: - State

    private var results: [WMFDepictsTag] = []
    private var searchTask: Task<Void, Never>?

    public var didTapClose: (() -> Void)?

    // MARK: - Subviews

    private lazy var searchBar: UISearchBar = {
        let bar = UISearchBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.searchBarStyle = .minimal
        bar.autocapitalizationType = .none
        bar.delegate = self
        bar.accessibilityIdentifier = "commons-tag-search-bar"
        return bar
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.accessibilityIdentifier = "commons-tag-search-results"
        return tableView
    }()

    // MARK: - Lifecycle

    public init(title: String, placeholder: String, performSearch: @escaping (String) async -> [WMFDepictsTag], isAlreadySelected: @escaping (WMFDepictsTag) -> Bool, onSelect: @escaping (WMFDepictsTag) -> Void) {
        self.title_ = title
        self.placeholder = placeholder
        self.performSearch = performSearch
        self.isAlreadySelected = isAlreadySelected
        self.onSelect = onSelect
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        searchBar.placeholder = placeholder
        view.addSubview(searchBar)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        updateColors()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureNavigationBar()
        searchBar.becomeFirstResponder()
    }

    public override func appEnvironmentDidChange() {
        super.appEnvironmentDidChange()
        updateColors()
    }

    private func configureNavigationBar() {
        let titleConfig = WMFNavigationBarTitleConfig(title: title_, customView: nil, alignment: .centerCompact)
        let closeConfig = WMFLargeCloseButtonConfig(imageType: .plainX, target: self, action: #selector(didTapCloseButton), alignment: .leading)
        configureNavigationBar(titleConfig: titleConfig, closeButtonConfig: closeConfig, profileButtonConfig: nil, tabsButtonConfig: nil, searchBarConfig: nil, hideNavigationBarOnScroll: false)
    }

    private func updateColors() {
        view.backgroundColor = theme.paperBackground
        tableView.backgroundColor = theme.paperBackground
        searchBar.searchTextField.textColor = theme.text
        tableView.reloadData()
    }

    @objc private func didTapCloseButton() {
        didTapClose?()
    }

    // MARK: - Searching

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchTask?.cancel()
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            results = []
            tableView.reloadData()
            return
        }
        searchTask = Task { [weak self] in
            guard let self else { return }
            // Small debounce so we don't fire a request on every keystroke.
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            let found = await self.performSearch(term)
            if Task.isCancelled { return }
            self.results = found
            self.tableView.reloadData()
        }
    }

    // MARK: - UITableViewDataSource / Delegate

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return results.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let tag = results[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = tag.label
        content.secondaryText = tag.description
        content.textProperties.color = theme.text
        content.secondaryTextProperties.color = theme.secondaryText
        cell.contentConfiguration = content
        cell.backgroundColor = theme.paperBackground
        cell.accessoryType = isAlreadySelected(tag) ? .checkmark : .none
        cell.selectionStyle = .default
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let tag = results[indexPath.row]
        onSelect(tag)
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    deinit {
        searchTask?.cancel()
    }
}
