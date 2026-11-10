import Foundation

/// JSON 解析接口（TVBox 里的 parses type = 1）
///
/// 约定：`GET <解析地址> + URL编码后的视频页地址`，返回一段 JSON，
/// 里面某个字段是真正的播放直链，比如：
///   {"code":200,"url":"https://xxx/index.m3u8?sign=..."}
///   {"data":{"url":"..."}}
/// 自建的解析服务（NAS 上跑的那种）按这个格式返回，口袋盒就能直接用。
enum ParseService {
    /// 拿到直链返回，拿不到返回 nil（交给后面的嗅探/网页兜底）
    static func resolve(parse: Parse, video: String) async -> String? {
        guard let url = PlaybackRouter.parseURL(parse: parse, video: video) else { return nil }

        var request = URLRequest(url: url)
        request.setValue(Net.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        guard let (data, _) = try? await Net.session.data(for: request), !data.isEmpty else { return nil }

        let text = (String(data: data, encoding: .utf8) ?? "")
            .replacingOccurrences(of: "\\/", with: "/")

        // 有的接口直接返回一段 JS（var url = "..."），先按文本抠
        if let direct = firstDirect(in: text) { return direct }

        // 标准 JSON：递归找第一个像直链的字符串
        if let root = try? JSONSerialization.jsonObject(with: data) {
            return firstDirect(inJSON: root)
        }
        return nil
    }

    /// 一堆解析器里挑出能给出直链的那个
    static func resolveAny(parses: [Parse], video: String) async -> String? {
        for parse in parses where parse.type == 1 {
            if let direct = await resolve(parse: parse, video: video) { return direct }
        }
        return nil
    }

    // MARK: - 提取

    private static let streamPattern = try! NSRegularExpression(
        pattern: #"https?://[^\s"'<>\\]+?\.(?:m3u8|mp4|flv)(?:\?[^\s"'<>\\]*)?"#,
        options: [.caseInsensitive]
    )

    private static func firstDirect(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = streamPattern.firstMatch(in: text, options: [], range: range),
              let matchRange = Range(match.range, in: text) else { return nil }
        return String(text[matchRange])
    }

    private static func firstDirect(inJSON value: Any, depth: Int = 0) -> String? {
        guard depth < 6 else { return nil }

        if let string = value as? String {
            let cleaned = string.replacingOccurrences(of: "\\/", with: "/")
            if cleaned.isHTTPURL, containsStream(cleaned) { return cleaned }
            return nil
        }

        if let dict = value as? [String: Any] {
            // 常见字段先看，命中率最高
            for key in ["url", "playUrl", "play_url", "m3u8", "src", "link", "video"] {
                if let string = dict[key] as? String {
                    let cleaned = string.replacingOccurrences(of: "\\/", with: "/")
                    if cleaned.isHTTPURL { return cleaned }
                }
            }
            for (_, child) in dict {
                if let found = firstDirect(inJSON: child, depth: depth + 1) { return found }
            }
            return nil
        }

        if let array = value as? [Any] {
            for child in array {
                if let found = firstDirect(inJSON: child, depth: depth + 1) { return found }
            }
            return nil
        }

        return nil
    }

    private static func containsStream(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains(".m3u8") || lower.contains(".mp4") || lower.contains(".flv")
    }
}
