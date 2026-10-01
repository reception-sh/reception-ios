import Reception
import UIKit

@MainActor
final class HomeViewController: UIViewController {
    private let supportButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "UIKit home"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Details", style: .plain, target: self, action: #selector(showDetails))
        supportButton.addTarget(self, action: #selector(openSupport), for: .touchUpInside)
        supportButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        supportButton.titleLabel?.adjustsFontForContentSizeCategory = true
        supportButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(supportButton)
        NSLayoutConstraint.activate([
            supportButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            supportButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            supportButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        observeUnreadCount { [weak self] count in
            self?.updateUnreadCount(count)
        }
    }

    func updateUnreadCount(_ count: Int) {
        supportButton.setTitle(count > 0 ? "Support (\(count))" : "Support", for: .normal)
        supportButton.accessibilityValue = count > 0 ? "\(count) unread messages" : nil
    }

    @objc private func showDetails() {
        let details = UIViewController()
        details.title = "Details"
        details.view.backgroundColor = .systemBackground
        details.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Support", style: .plain, target: self, action: #selector(openSupport))
        navigationController?.pushViewController(details, animated: true)
    }

    @objc private func openSupport() { Reception.shared.openChat() }
}
