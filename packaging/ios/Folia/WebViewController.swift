import UIKit
import WebKit

// 加载 Folia 服务端网页的主界面：只有同一个服务端的页面留在 App 里，外链交给 Safari；
// 补上 WKWebView 默认不处理的弹窗、新窗口和文件下载；摇一摇可以刷新或更换服务端。

final class WebViewController: UIViewController {
    private var webView: WKWebView!
    private let statusView = StatusView()
    private var server: URL?
    // 当前服务端的页面加载成功过一次后，后续的加载失败不再盖住页面
    private var hasLoadedPage = false
    // 留在 App 里打开的网站：服务端本身，加上首次加载时经过的跳转（http 跳 https、反向代理前面的登录页）
    private var trustedOrigins: [URL] = []
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        setUpWebView()
        setUpStatusView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard server == nil else { return }
        if let saved = ServerSettings.current {
            load(saved)
        } else {
            askForServer(canCancel: false)
        }
    }

    override var canBecomeFirstResponder: Bool { true }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else { return }
        showAppMenu()
    }

    // MARK: - 界面

    private func setUpWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        // 保留 Safari 的标识，网页按移动版 Safari 处理；FoliaiOS 方便服务端日志区分来源
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        configuration.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1 FoliaiOS/\(version)"

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = Theme.background
        webView.scrollView.backgroundColor = Theme.background
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        if #available(iOS 16.4, *) {
            // 连上 Mac 后可以用 Safari 的“开发”菜单调试页面
            webView.isInspectable = true
        }

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        // 网页没有处理刘海和底部横条（viewport 没写 viewport-fit=cover），所以页面只铺在安全区里
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: guide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
        ])
    }

    private func setUpStatusView() {
        statusView.translatesAutoresizingMaskIntoConstraints = false
        statusView.onRetry = { [weak self] in
            guard let self, let server = self.server else { return }
            self.load(server)
        }
        statusView.onChangeServer = { [weak self] in
            self?.askForServer(canCancel: true)
        }
        view.addSubview(statusView)
        NSLayoutConstraint.activate([
            statusView.topAnchor.constraint(equalTo: view.topAnchor),
            statusView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    // MARK: - 服务端

    private func load(_ url: URL) {
        server = url
        trustedOrigins = [url]
        hasLoadedPage = false
        statusView.showLoading(server: url)
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    private func askForServer(canCancel: Bool) {
        let alert = UIAlertController(
            title: "Folia 服务端地址",
            message: "填写已经部署好的 Folia 网页版地址（Docker 或 Vercel），例如 https://folia.example.com 或 http://192.168.1.10:18080。\n之后摇一摇手机可以更换。",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "https://folia.example.com"
            field.text = (self.server ?? ServerSettings.current)?.absoluteString
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        if canCancel {
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        }
        alert.addAction(UIAlertAction(title: "连接", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            guard let url = ServerSettings.normalize(alert?.textFields?.first?.text ?? "") else {
                self.showMessage("地址无效", "请填写 http:// 或 https:// 开头的地址。") {
                    self.askForServer(canCancel: canCancel)
                }
                return
            }
            ServerSettings.save(url)
            self.load(url)
        })
        presentOnTop(alert)
    }

    private func showAppMenu() {
        let sheet = UIAlertController(title: "Folia", message: server?.absoluteString, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "刷新页面", style: .default) { [weak self] _ in
            guard let self else { return }
            if self.hasLoadedPage {
                self.webView.reload()
            } else if let server = self.server {
                self.load(server)
            }
        })
        sheet.addAction(UIAlertAction(title: "更换服务端", style: .default) { [weak self] _ in
            self?.askForServer(canCancel: true)
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presentOnTop(sheet)
    }

    // MARK: - 工具

    private func presentOnTop(_ controller: UIViewController) {
        var top: UIViewController = self
        while let presented = top.presentedViewController {
            top = presented
        }
        top.present(controller, animated: true)
    }

    private func showMessage(_ title: String, _ message: String, then: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in then?() })
        presentOnTop(alert)
    }

    private func isTrusted(_ url: URL) -> Bool {
        trustedOrigins.contains { ServerSettings.isSameServer(url, as: $0) }
    }

    private func openExternally(_ url: URL) {
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                NSLog("[FoliaiOS] 无法打开外部链接: %@", url.absoluteString)
            }
        }
    }

    private func isIgnorableLoadError(_ error: Error) -> Bool {
        let nsError = error as NSError
        // 被新的导航取消；或者这次导航变成了下载（WebKitErrorFrameLoadInterruptedByPolicyChange）
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return true }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return true }
        return false
    }

    private func handleMainFrameFailure(_ error: Error) {
        guard !isIgnorableLoadError(error) else { return }
        NSLog("[FoliaiOS] 页面加载失败: %@", String(describing: error))
        if !hasLoadedPage {
            statusView.showFailure(server: server, message: error.localizedDescription)
        }
    }

    private func shareFile(at url: URL) {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 40, width: 0, height: 0)
        }
        presentOnTop(activity)
    }
}

// MARK: - 导航

extension WebViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }
        // 网页内部用的 about:、blob:、data: 照常加载
        if ["about", "blob", "data"].contains(scheme) {
            decisionHandler(.allow)
            return
        }
        // 其他 App 的链接（音乐平台 App、App Store 等）交给系统
        guard scheme == "http" || scheme == "https" else {
            openExternally(url)
            decisionHandler(.cancel)
            return
        }
        // iframe 里的内容不管来源都在页面里加载；只有整页跳到别的网站才交给 Safari
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if isMainFrame && !isTrusted(url) {
            if hasLoadedPage {
                openExternally(url)
                decisionHandler(.cancel)
                return
            }
            // 页面还没打开过：这是服务端自己的跳转，跟着走，并把跳到的网站也留在 App 里
            if let origin = ServerSettings.normalize(url.absoluteString) {
                trustedOrigins.append(origin)
            }
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasLoadedPage = true
        statusView.hide()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleMainFrameFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleMainFrameFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // 系统回收了网页进程（内存紧张时常见），重新加载，不留白屏
        NSLog("[FoliaiOS] 网页进程被系统结束，重新加载")
        if hasLoadedPage {
            webView.reload()
        } else if let server {
            load(server)
        }
    }
}

// MARK: - 弹窗和新窗口

extension WebViewController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // window.open / target=_blank：同一服务端的页面在当前页打开，外链交给 Safari
        if let url = navigationAction.request.url {
            if isTrusted(url) {
                webView.load(navigationAction.request)
            } else if url.scheme != nil, url.scheme != "about" {
                openExternally(url)
            }
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        presentOnTop(alert)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        presentOnTop(alert)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text)
        })
        presentOnTop(alert)
    }
}

// MARK: - 下载

extension WebViewController: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        // 每次下载放进自己的临时目录，保留网页给的文件名，下完用分享面板存到“文件”或发给别的 App
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            NSLog("[FoliaiOS] 无法创建下载目录: %@", String(describing: error))
            completionHandler(nil)
            return
        }
        let name = suggestedFilename.isEmpty ? "download" : suggestedFilename
        let destination = folder.appendingPathComponent(name)
        downloadDestinations[ObjectIdentifier(download)] = destination
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let destination = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        NSLog("[FoliaiOS] 下载完成: %@", destination.lastPathComponent)
        shareFile(at: destination)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        NSLog("[FoliaiOS] 下载失败: %@", String(describing: error))
        showMessage("下载失败", error.localizedDescription)
    }
}
