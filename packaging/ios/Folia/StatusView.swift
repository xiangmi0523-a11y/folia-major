import UIKit

// 页面打开前盖在网页上面的状态层：连接中显示转圈，连不上时显示原因和“重试”“更换服务端”。

final class StatusView: UIView {
    var onRetry: (() -> Void)?
    var onChangeServer: (() -> Void)?

    private let spinner = UIActivityIndicatorView(style: .large)
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let changeButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.background

        spinner.color = .white
        spinner.hidesWhenStopped = true

        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        detailLabel.textColor = UIColor(white: 1, alpha: 0.6)
        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0

        retryButton.setTitle("重试", for: .normal)
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
        changeButton.setTitle("更换服务端", for: .normal)
        changeButton.addAction(UIAction { [weak self] _ in self?.onChangeServer?() }, for: .touchUpInside)
        for button in [retryButton, changeButton] {
            button.titleLabel?.font = .preferredFont(forTextStyle: .body)
            button.tintColor = UIColor(red: 0xB6 / 255.0, green: 0xBA / 255.0, blue: 0xF3 / 255.0, alpha: 1)
        }

        let buttons = UIStackView(arrangedSubviews: [retryButton, changeButton])
        buttons.axis = .horizontal
        buttons.spacing = 32

        let stack = UIStackView(arrangedSubviews: [spinner, titleLabel, detailLabel, buttons])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor, constant: -16),
        ])

        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showLoading(server: URL) {
        isHidden = false
        alpha = 1
        spinner.startAnimating()
        titleLabel.text = "正在连接 Folia"
        detailLabel.text = server.absoluteString
        retryButton.isHidden = true
        changeButton.isHidden = true
    }

    func showFailure(server: URL?, message: String) {
        isHidden = false
        alpha = 1
        spinner.stopAnimating()
        titleLabel.text = "连不上 Folia 服务端"
        detailLabel.text = [server?.absoluteString, message].compactMap { $0 }.joined(separator: "\n")
        retryButton.isHidden = false
        changeButton.isHidden = false
    }

    func hide() {
        guard !isHidden else { return }
        spinner.stopAnimating()
        UIView.animate(withDuration: 0.25, animations: { self.alpha = 0 }, completion: { _ in
            // 动画期间又调了 showLoading / showFailure 时不要藏起来
            if self.alpha == 0 { self.isHidden = true }
        })
    }
}
