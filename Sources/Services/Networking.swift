import Foundation

enum NetError: LocalizedError {
    case badURL
    case http(Int)
    case decode
    case notJSON(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "地址不合法"
        case .http(let code): return "服务器返回 \(code)"
        case .decode: return "数据格式无法解析"
        case .notJSON(let detail): return detail
        }
    }
}

enum Net {
    /// 可配置的 UA。部分接口服务器会按 UA 分流（浏览器 UA 会被跳到网页/提示图），
    /// 遇到这类接口时把这里改成 okhttp 即可。
    static var userAgent = "okhttp/3.12.0"

    /// 豆瓣这类站点只认浏览器 UA
    static let browserUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.2 Mobile/15E148 Safari/604.1"

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    static func data(from url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...399).contains(http.statusCode) {
            throw NetError.http(http.statusCode)
        }
        return data
    }

    static func fetch(_ urlString: String) async throws -> Data {
        guard let normalized = IDN.normalize(urlString),
              let url = URL(string: normalized) else { throw NetError.badURL }
        return try await data(from: url)
    }

    static func jsonRoot(_ url: URL) async throws -> [String: Any] {
        let data = try await data(from: url)
        let raw = try? JSONSerialization.jsonObject(with: data)
        if let root = raw as? [String: Any] { return root }
        throw Self.notJSONError(data)
    }

    /// 对"接口其实已经挂了"给出人话报错：返回网页、占位图片等
    private static func notJSONError(_ data: Data) -> Error {
        let prefix = (String(data: data.prefix(120), encoding: .utf8) ?? "").trimmed().lowercased()
        if prefix.hasPrefix("<") || prefix.hasPrefix("<!doctype") || prefix.contains("<html") {
            return NetError.notJSON("接口返回的是网页而不是 JSON——地址可能已失效，或被跳转到了提示页/导航页")
        }
        let imageMagics: [[UInt8]] = [
            [0x89, 0x50, 0x4E, 0x47],   // PNG
            [0xFF, 0xD8, 0xFF],          // JPEG
            [0x47, 0x49, 0x46],          // GIF
            [0x52, 0x49, 0x46, 0x46]     // WEBP (RIFF)
        ]
        if imageMagics.contains(where: { data.starts(with: $0) }) {
            return NetError.notJSON("接口返回了一张图片而不是 JSON——常见于接口失效后作者放的占位图，去发布页找新地址吧")
        }
        return NetError.decode
    }

    /// 拼接 query，自动处理接口地址里已带 ? 或已有同名参数的情况，并兼容中文域名
    static func makeURL(_ base: String, _ params: [(String, String)]) -> URL? {
        guard let normalized = IDN.normalize(base),
              var components = URLComponents(string: normalized) else { return nil }
        var items = components.queryItems ?? []
        for (name, value) in params {
            items.removeAll { $0.name == name }
            items.append(URLQueryItem(name: name, value: value))
        }
        components.queryItems = items
        return components.url
    }
}

extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isHTTPURL: Bool {
        let lower = lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmed()
    }
}

/// 从 JSON 里安全取值
enum JSONValue {
    static func string(_ any: Any?) -> String {
        switch any {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        case let value as [String: Any]:
            if let data = try? JSONSerialization.data(withJSONObject: value),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            return ""
        case let value as [Any]:
            if let data = try? JSONSerialization.data(withJSONObject: value),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            return ""
        default:
            return ""
        }
    }

    static func int(_ any: Any?, fallback: Int) -> Int {
        if let number = any as? NSNumber { return number.intValue }
        if let text = any as? String, let value = Int(text) { return value }
        return fallback
    }

    static func bool(_ any: Any?, fallback: Bool) -> Bool {
        if let number = any as? NSNumber { return number.boolValue }
        if let text = any as? String {
            let lower = text.lowercased()
            return text == "1" || lower == "true" || lower == "yes"
        }
        return fallback
    }
}
