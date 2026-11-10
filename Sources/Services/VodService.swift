import Foundation

/// 苹果CMS / MacCMS V10 标准 JSON 接口（type 1）
/// 以及 drpy/T4 服务端源（type 4，api 为完整 HTTP 地址，如 http://ip:5705/vod?pwd=x&rule=y）
enum VodService {
    static func categories(site: Site) async throws -> [Category] {
        if site.isT4 {
            // T4 首页（不带参数）返回 {class, list}
            guard let url = Net.makeURL(site.api, []) else { throw NetError.badURL }
            let root = try await Net.jsonRoot(url)
            return categories(from: root)
        }

        guard let url = Net.makeURL(site.api, [("ac", "list")]) else { throw NetError.badURL }
        let root = try await Net.jsonRoot(url)
        return categories(from: root)
    }

    private static func categories(from root: [String: Any]) -> [Category] {
        guard let rows = root["class"] as? [[String: Any]] else { return [Category(id: "", name: "全部")] }
        let list = rows.compactMap { dict -> Category? in
            let id = JSONValue.string(dict["type_id"]).trimmed()
            let name = JSONValue.string(dict["type_name"]).trimmed()
            guard !id.isEmpty, !name.isEmpty else { return nil }
            return Category(id: id, name: name)
        }
        return list.isEmpty ? [Category(id: "", name: "全部")] : list
    }

    static func list(site: Site, categoryId: String, page: Int) async throws -> (items: [VodItem], pageCount: Int) {
        var params: [(String, String)] = [("ac", "videolist"), ("pg", String(page))]
        if !categoryId.isEmpty { params.append(("t", categoryId)) }
        guard let url = Net.makeURL(site.api, params) else { throw NetError.badURL }
        return try await request(url)
    }

    static func search(site: Site, keyword: String) async throws -> [VodItem] {
        guard let url = Net.makeURL(site.api, [("ac", "videolist"), ("wd", keyword), ("pg", "1")]) else {
            throw NetError.badURL
        }
        return try await request(url).items
    }

    static func detail(site: Site, id: String) async throws -> VodItem? {
        // CMS 用 ac=videolist&ids；drpy/T4 约定 ac=detail
        let ac = site.isT4 ? "detail" : "videolist"
        guard let url = Net.makeURL(site.api, [("ac", ac), ("ids", id)]) else { throw NetError.badURL }
        return try await request(url).items.first
    }

    private static func request(_ url: URL) async throws -> (items: [VodItem], pageCount: Int) {
        let root = try await Net.jsonRoot(url)
        let rows = (root["list"] as? [[String: Any]]) ?? []
        let items = rows.map { item(from: $0) }.filter { !$0.id.isEmpty }
        let pageCount = max(JSONValue.int(root["pagecount"], fallback: 1), 1)
        return (items, pageCount)
    }

    static func item(from dict: [String: Any]) -> VodItem {
        let flags = JSONValue.string(dict["vod_play_from"])
            .components(separatedBy: "$$$")
            .map { $0.trimmed() }
        let blocks = JSONValue.string(dict["vod_play_url"]).components(separatedBy: "$$$")

        var groups: [PlayGroup] = []
        for (index, block) in blocks.enumerated() {
            let episodes = parseEpisodes(block)
            guard !episodes.isEmpty else { continue }
            var name = index < flags.count ? flags[index] : ""
            if name.isEmpty { name = "线路\(index + 1)" }
            groups.append(PlayGroup(name: name, episodes: episodes))
        }

        return VodItem(
            id: JSONValue.string(dict["vod_id"]).trimmed(),
            name: JSONValue.string(dict["vod_name"]).trimmed(),
            pic: JSONValue.string(dict["vod_pic"]).trimmed(),
            remarks: JSONValue.string(dict["vod_remarks"]).trimmed(),
            year: JSONValue.string(dict["vod_year"]).trimmed(),
            area: JSONValue.string(dict["vod_area"]).trimmed(),
            typeName: JSONValue.string(dict["type_name"]).trimmed(),
            actor: JSONValue.string(dict["vod_actor"]).trimmed(),
            director: JSONValue.string(dict["vod_director"]).trimmed(),
            content: JSONValue.string(dict["vod_content"]).strippingHTML,
            groups: groups
        )
    }

    /// "第1集$http://a.m3u8#第2集$http://b.m3u8"
    static func parseEpisodes(_ block: String) -> [Episode] {
        block.components(separatedBy: "#").compactMap { rawLine in
            let line = rawLine.trimmed()
            guard !line.isEmpty else { return nil }
            let parts = line.components(separatedBy: "$")
            if parts.count >= 2, let url = parts.last?.trimmed(), url.isHTTPURL {
                let name = parts.dropLast().joined(separator: "$").trimmed()
                return Episode(name: name.isEmpty ? "播放" : name, url: url)
            }
            return line.isHTTPURL ? Episode(name: line, url: line) : nil
        }
    }
}
