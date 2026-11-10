import Foundation

/// T4 / drpy 服务端源的"免嗅探"播放解析。
/// 把播放页地址（vod_play_url 里拿到的）通过 play_url 参数交给服务端，
/// 服务端完成嗅探后返回 m3u8 直链（JSON 或 302 重定向）。
enum Type4Service {
    struct ResolvedPlay: Identifiable, Hashable {
        var id = UUID()
        var url: URL
    }

    static func resolve(site: Site, episodeURL: String) async throws -> ResolvedPlay {
        guard let url = Net.makeURL(site.api, [("play_url", episodeURL)]) else { throw NetError.badURL }

        var request = URLRequest(url: url)
        request.setValue(Net.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await Net.session.data(for: request)
        let finalURL = response.url ?? url

        // 1) JSON：{"parse":0,"playUrl":"","jx":0,"url":"https://...m3u8"}
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["url", "playUrl", "play_url", "jx"] {
                let link = JSONValue.string(obj[key]).trimmed()
                if link.isHTTPURL, let target = URL(string: link) {
                    return ResolvedPlay(url: target)
                }
            }
        }

        // 2) 302 重定向到直链 / 直接返回 m3u8 内容：最终请求地址就是可播地址
        let contentType = ((response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let bodyHead = String(data: data.prefix(200), encoding: .utf8) ?? ""
        if contentType.contains("mpegurl") || contentType.contains("video")
            || bodyHead.trimmed().hasPrefix("#EXTM3U") {
            return ResolvedPlay(url: finalURL)
        }

        throw NetError.notJSON("服务端没有解析出可播放的直链（源可能已失效，或这条线路不支持免嗅探）")
    }
}
