import Foundation

// 服务端地址的读写：用户填的地址存在 UserDefaults，没填过时用构建时写进 Info.plist 的默认地址。

enum ServerSettings {
    private static let storageKey = "FoliaServerURL"

    /// 当前要加载的服务端；用户和构建都没给地址时为 nil。
    static var current: URL? {
        if let saved = UserDefaults.standard.string(forKey: storageKey), let url = normalize(saved) {
            return url
        }
        return buildDefault
    }

    /// 构建时通过 FOLIA_DEFAULT_SERVER_URL 写进 Info.plist 的地址。
    static var buildDefault: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "FoliaDefaultServerURL") as? String else {
            return nil
        }
        return normalize(value)
    }

    static func save(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: storageKey)
    }

    /// 把输入整理成服务端根地址：去空白、没写协议时补 https://、去掉路径和结尾斜杠。不是 http(s) 地址时返回 nil。
    static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if !text.contains("://") {
            text = "https://" + text
        }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else {
            return nil
        }
        components.scheme = scheme
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// 同一个服务端（协议、主机、端口都相同）的页面留在 App 里打开，其他的交给 Safari。
    static func isSameServer(_ url: URL, as server: URL) -> Bool {
        guard url.scheme?.lowercased() == server.scheme?.lowercased(),
              url.host?.lowercased() == server.host?.lowercased()
        else {
            return false
        }
        return effectivePort(url) == effectivePort(server)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }
}
