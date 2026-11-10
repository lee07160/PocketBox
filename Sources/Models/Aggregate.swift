import Foundation

// MARK: - 搜索结果条目

/// 一条搜索结果：某个站点里的某个条目
struct SearchHit: Identifiable, Hashable {
    var siteKey: String
    var item: VodItem

    var id: String { siteKey + "|" + item.id }
}

// MARK: - 片名归一化

/// 把不同站点对同一部片的写法收敛到同一个 key
/// 「庆余年 第二季(4K)」「庆余年第二季」→ 同一个 key
enum TitleKey {
    /// 常见的清晰度 / 版本 / 语言标注，出现在片名括号里或末尾时直接丢掉
    private static let noiseTokens: [String] = [
        "国语", "粤语", "国粤双语", "双语", "中字", "中文字幕", "字幕", "无字",
        "高清", "超清", "蓝光", "完整版", "未删减", "未删减版", "导演剪辑版",
        "抢先版", "枪版", "tc", "ts", "hd", "bd", "hdrip", "webrip", "web-dl",
        "4k", "8k", "1080p", "720p", "2160p", "60帧", "高码", "修复版", "重制版",
        "tv版", "剧场版", "电影版", "更新至"
    ]

    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return "" }

        // 全角 → 半角，顺便统一括号
        text = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text

        // 去掉括号及其内容：() [] 【】 <> 里的基本都是版本标注
        text = stripBracketed(text, open: "(", close: ")")
        text = stripBracketed(text, open: "[", close: "]")
        text = stripBracketed(text, open: "<", close: ">")

        // 去掉末尾反复出现的噪声词
        var changed = true
        while changed {
            changed = false
            for token in noiseTokens where text.hasSuffix(token) {
                text = String(text.dropLast(token.count))
                changed = true
            }
        }

        // 只保留文字与数字，去掉空格、标点、符号
        var cleanedView = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                cleanedView.append(scalar)
            }
        }
        let cleaned = String(cleanedView)
        // 归一化完变成空串（比如片名全是符号）时退回原文小写
        return cleaned.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : cleaned
    }

    private static func stripBracketed(_ text: String, open: Character, close: Character) -> String {
        var result = ""
        var depth = 0
        for char in text {
            if char == open {
                depth += 1
            } else if char == close {
                if depth > 0 { depth -= 1 }
            } else if depth == 0 {
                result.append(char)
            }
        }
        return result
    }
}

// MARK: - 片名分组

/// 同一部片在所有站点里的全部条目
struct TitleGroup: Identifiable, Hashable {
    var key: String
    var name: String
    /// 已按「集数多的源在前」排序
    var hits: [SearchHit]

    var id: String { key }

    /// 用来展示封面/简介的条目：优先有封面的
    var primary: SearchHit {
        if let withPic = hits.first(where: { !$0.item.pic.isEmpty }) { return withPic }
        return hits.first ?? SearchHit(siteKey: "", item: VodItem(id: ""))
    }

    var sourceCount: Int { hits.count }

    var year: String { primary.item.year }

    var subtitle: String { primary.item.subtitle }

    /// 这片最多能拿到多少集，用于排序与展示
    var maxEpisodeCount: Int {
        hits.map { $0.item.bestEpisodeCount }.max() ?? 0
    }
}

enum TitleGrouper {
    /// 把「按站点铺开」的搜索结果聚合成「按片名一条」
    static func groups(from hits: [SearchHit]) -> [TitleGroup] {
        var buckets: [String: [SearchHit]] = [:]
        var order: [String] = []
        var seenHit = Set<String>()

        for hit in hits {
            guard !hit.item.name.isEmpty else { continue }
            guard seenHit.insert(hit.id).inserted else { continue }
            let key = TitleKey.normalize(hit.item.name)
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(hit)
        }

        let groups: [TitleGroup] = order.compactMap { key in
            guard var list = buckets[key], !list.isEmpty else { return nil }
            // 集数多的源排前面，用户点进去默认就能播到最全的那个
            list.sort { lhs, rhs in
                if lhs.item.bestEpisodeCount != rhs.item.bestEpisodeCount {
                    return lhs.item.bestEpisodeCount > rhs.item.bestEpisodeCount
                }
                return lhs.siteKey < rhs.siteKey
            }
            let display = list.first(where: { !$0.item.pic.isEmpty })?.item.name ?? list[0].item.name
            return TitleGroup(key: key, name: display, hits: list)
        }

        // 源多的（说明热门/资源全）排在前面，其次按片名稳定排序
        return groups.sorted { lhs, rhs in
            if lhs.sourceCount != rhs.sourceCount { return lhs.sourceCount > rhs.sourceCount }
            return lhs.name < rhs.name
        }
    }
}

extension VodItem {
    /// 单条线路最多多少集
    var bestEpisodeCount: Int {
        groups.map { $0.episodes.count }.max() ?? 0
    }

    var hasPlayableEpisodes: Bool {
        groups.contains { !$0.episodes.isEmpty }
    }
}
