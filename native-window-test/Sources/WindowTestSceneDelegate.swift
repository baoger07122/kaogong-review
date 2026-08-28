import UIKit

final class WindowTestSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let viewController = WindowTestViewController()
        viewController.navigationItem.title = "窗口工具栏测试"
        viewController.navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: nil,
            action: nil
        )
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.navigationBar.prefersLargeTitles = false
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        self.window = window
    }

    @available(iOS 26.0, *)
    func preferredWindowingControlStyle(
        for scene: UIWindowScene
    ) -> UIWindowScene.WindowingControlStyle {
        .unified
    }
}

private final class WindowTestViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let icon = UIImageView(image: UIImage(systemName: "macwindow.on.rectangle"))
        icon.tintColor = .systemBlue
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "窗口控件专项测试"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textAlignment = .center

        let statusLabel = UILabel()
        statusLabel.text = "UIKit SceneDelegate 已正常运行"
        statusLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        statusLabel.textColor = .systemGreen
        statusLabel.textAlignment = .center

        let detailLabel = UILabel()
        detailLabel.text = "版本 8.28.8 · Unified + UINavigationBar\n本测试加入系统原生顶部工具栏。\n请只观察左上角三点是否进入工具栏并与系统信息合并。"
        detailLabel.font = .systemFont(ofSize: 15, weight: .regular)
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, statusLabel, detailLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.heightAnchor.constraint(equalToConstant: 72),
            stack.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 520)
        ])
    }
}
