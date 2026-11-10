import Foundation

// MARK: - 媒体类型

enum DoubanMedia: String, CaseIterable, Identifiable {
    case movie
    case tv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movie: return "电影"
        case .tv: return "剧集"
        }
    }
}

// MARK: - 榜单

enum DoubanBoard: String, CaseIterable, Identifiable {
    case movieHot, movieNew, movieHigh, movieChinese, movieWestern, movieKorean, movieJapanese
    case tvHot, tvChinese, tvUS, tvUK, tvKorean, tvJapanese, tvVariety, tvDoc, tvAnime

    var id: String { rawValue }

    var media: DoubanMedia {
        switch self {
        case .movieHot, .movieNew, .movieHigh, .movieChinese, .movieWestern, .movieKorean, .movieJapanese:
            return .movie
        default:
            return .tv
        }
    }

    var type: String { media.rawValue }

    var title: String {
        switch self {
        case .movieHot: return "热门"
        case .movieNew: return "最新"
        case .movieHigh: return "豆瓣高分"
        case .movieChinese: return "华语"
        case .movieWestern: return "欧美"
        case .movieKorean: return "韩国"
        case .movieJapanese: return "日本"
        case .tvHot: return "热门"
        case .tvChinese: return "国产剧"
        case .tvUS: return "美剧"
        case .tvUK: return "英剧"
        case .tvKorean: return "韩剧"
        case .tvJapanese: return "日剧"
        case .tvVariety: return "综艺"
        case .tvDoc: return "纪录片"
        case .tvAnime: return "日本动画"
        }
    }

    /// 对应豆瓣 j/search_subjects 的 tag 参数
    var tag: String {
        switch self {
        case .movieHot: return "热门"
        case .movieNew: return "最新"
        case .movieHigh: return "豆瓣高分"
        case .movieChinese: return "华语"
        case .movieWestern: return "欧美"
        case .movieKorean: return "韩国"
        case .movieJapanese: return "日本"
        case .tvHot: return "热门"
        case .tvChinese: return "国产剧"
        case .tvUS: return "美剧"
        case .tvUK: return "英剧"
        case .tvKorean: return "韩剧"
        case .tvJapanese: return "日剧"
        case .tvVariety: return "综艺"
        case .tvDoc: return "纪录片"
        case .tvAnime: return "日本动画"
        }
    }

    static func boards(for media: DoubanMedia) -> [DoubanBoard] {
        allCases.filter { $0.media == media }
    }
}

// MARK: - 榜单项

struct DoubanSubject: Identifiable, Hashable {
    var id: String
    var title: String
    var rate: String
    var cover: String
    var url: String
    var episodesInfo: String
    var isNew: Bool
    var playable: Bool

    /// 用于去采集站搜索的片名：去掉零宽字符和尾部的年份
    var searchTitle: String {
        var text = title
        let junk = CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{200E}\u{200F}\u{FEFF}")
        text = text.components(separatedBy: junk).joined()
        // "后会友期 (2026)" → "后会友期"
        if let range = text.range(of: #"\s*[\(（]\s*\d{4}\s*[\)）]\s*$"#, options: .regularExpression) {
            text = String(text[..<range.lowerBound])
        }
        return text.trimmed()
    }

    var rateText: String { rate.isEmpty ? "暂无" : rate }

    var badge: String {
        if !episodesInfo.isEmpty { return episodesInfo }
        if isNew { return "新" }
        return ""
    }
}

// MARK: - 豆瓣详情

struct DoubanAbstract: Hashable {
    var id: String
    var title: String
    var rate: String
    var year: String
    var types: [String]
    var region: String
    var duration: String
    var directors: [String]
    var actors: [String]
    var episodes: String
    var comment: String
    var isTV: Bool

    var subtitle: String {
        var parts: [String] = []
        if !year.isEmpty { parts.append(year) }
        if !region.isEmpty { parts.append(region) }
        if !types.isEmpty { parts.append(types.joined(separator: "/")) }
        if !duration.isEmpty, !isTV { parts.append(duration) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 服务

enum DoubanService {
    static let referer = "https://movie.douban.com/"

    static var requestHeaders: [String: String] {
        [
            "Referer": referer,
            "User-Agent": Net.browserUA,
            "Accept": "application/json, text/plain, */*",
        ]
    }

    /// 拉某个榜单；limit 最大 100
    static func board(_ board: DoubanBoard, limit: Int = 60) async throws -> [DoubanSubject] {
        let params: [(String, String)] = [
            ("type", board.type),
            ("tag", board.tag),
            ("sort", "recommend"),
            ("page_limit", String(limit)),
            ("page_start", "0"),
        ]
        guard let url = Net.makeURL("https://movie.douban.com/j/search_subjects", params) else {
            throw NetError.badURL
        }
        let data = try await Net.data(from: url, headers: requestHeaders)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetError.decode
        }
        if let message = root["msg"] as? String, !message.isEmpty {
            throw NetError.notJSON(doubanMessage(message))
        }
        let rows = (root["subjects"] as? [[String: Any]]) ?? []
        let list: [DoubanSubject] = rows.compactMap { dict in
            let id = JSONValue.string(dict["id"]).trimmed()
            let title = JSONValue.string(dict["title"]).trimmed()
            guard !id.isEmpty, !title.isEmpty else { return nil }
            return DoubanSubject(
                id: id,
                title: title,
                rate: JSONValue.string(dict["rate"]).trimmed(),
                cover: JSONValue.string(dict["cover"]).trimmed(),
                url: JSONValue.string(dict["url"]).trimmed(),
                episodesInfo: JSONValue.string(dict["episodes_info"]).trimmed(),
                isNew: JSONValue.bool(dict["is_new"], fallback: false),
                playable: JSONValue.bool(dict["playable"], fallback: false)
            )
        }
        if list.isEmpty { throw NetError.notJSON("豆瓣这个榜单暂时没有数据（可能被限流了），下拉刷新试试") }
        return list
    }

    /// 详情：类型、地区、演员、短评等
    static func abstract(id: String) async throws -> DoubanAbstract? {
        guard let url = Net.makeURL("https://movie.douban.com/j/subject_abstract", [("subject_id", id)]) else {
            throw NetError.badURL
        }
        let data = try await Net.data(from: url, headers: requestHeaders)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dict = root["subject"] as? [String: Any] else { return nil }

        let title = JSONValue.string(dict["title"])
            .replacingOccurrences(of: "\u{200E}", with: "")
            .trimmed()
        // "后会友期 (2026)" → 片名 / 年份
        var name = title
        var year = JSONValue.string(dict["release_year"]).trimmed()
        if let range = name.range(of: #"\s*[\(（]\s*(\d{4})\s*[\)）]\s*$"#, options: .regularExpression) {
            if year.isEmpty {
                year = String(name[range]).replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            }
            name = String(name[..<range.lowerBound])
        }

        let comment = (dict["short_comment"] as? [String: Any]).map { JSONValue.string($0["content"]).trimmed() } ?? ""

        return DoubanAbstract(
            id: id,
            title: name.trimmed(),
            rate: JSONValue.string(dict["rate"]).trimmed(),
            year: year,
            types: (dict["types"] as? [String]) ?? [],
            region: JSONValue.string(dict["region"]).trimmed(),
            duration: JSONValue.string(dict["duration"]).trimmed(),
            directors: (dict["directors"] as? [String]) ?? [],
            actors: (dict["actors"] as? [String]) ?? [],
            episodes: JSONValue.string(dict["episodes_count"]).trimmed(),
            comment: comment,
            isTV: JSONValue.bool(dict["is_tv"], fallback: false)
        )
    }

    private static func doubanMessage(_ raw: String) -> String {
        if raw.contains("异常") || raw.contains("频繁") {
            return "豆瓣提示访问太频繁，等半分钟再下拉刷新"
        }
        return raw
    }
}
