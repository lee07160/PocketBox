import Foundation

/// 平台线路识别
///
/// 有一类采集源（iBox 那种「平台聚合源」）返回的不是 m3u8 直链，而是
/// 腾讯视频 / 爱奇艺 / 优酷 / 芒果 / B 站 的**网页地址**，必须靠解析服务
/// 才能换成直链。识别出来的用途有两个：
/// 1. 播放时不再白等嗅探（这类页面里本来就抠不出 m3u8），直接进网页播放；
/// 2. 聚合选源时把它们排在直链源后面，并标注「平台线路」。
enum PlatformLink {
    /// 顺序有讲究：先匹配更具体的子域
    private static let table: [(host: String, name: String)] = [
        ("v.qq.com", "腾讯视频"),
        ("m.v.qq.com", "腾讯视频"),
        ("qq.com", "腾讯视频"),
        ("iqiyi.com", "爱奇艺"),
        ("youku.com", "优酷"),
        ("mgtv.com", "芒果TV"),
        ("bilibili.com", "B站"),
        ("b23.tv", "B站"),
        ("sohu.com", "搜狐视频"),
        ("le.com", "乐视"),
        ("miguvideo.com", "咪咕视频"),
        ("pptv.com", "PPTV"),
        ("ixigua.com", "西瓜视频"),
        ("wasu.cn", "华数")
    ]

    /// 命中平台域名时返回平台名（用于提示文案）
    static func platform(of urlString: String) -> String? {
        let trimmed = urlString.trimmed()
        guard trimmed.isHTTPURL, let host = URL(string: trimmed)?.host?.lowercased() else { return nil }
        for row in table where host == row.host || host.hasSuffix("." + row.host) {
            return row.name
        }
        return nil
    }
}

extension VodItem {
    /// 有线路，且每一条都落在平台域名上 → 只能靠网页解析播
    /// （搜索接口偶尔不返回播放地址，这种情况按「未知」处理，不算平台源）
    var isPlatformOnly: Bool {
        let all = groups.flatMap { $0.episodes }
        guard !all.isEmpty else { return false }
        return all.allSatisfy { PlatformLink.platform(of: $0.url) != nil }
    }

    /// 至少有一条真直链（m3u8/mp4）
    var hasDirectEpisode: Bool {
        groups.contains { group in
            group.episodes.contains { !$0.url.isEmpty && PlatformLink.platform(of: $0.url) == nil }
        }
    }
}
