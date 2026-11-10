import Foundation

/// 跨站点并发搜索 + 片名聚合，搜索页和豆瓣榜单共用
enum Aggregator {
    /// 在所有可搜索站点里并发搜索，返回去重后的结果
    static func search(sites: [Site], keyword: String) async -> [SearchHit] {
        let query = keyword.trimmed()
        guard !query.isEmpty, !sites.isEmpty else { return [] }

        var hits: [SearchHit] = []
        await withTaskGroup(of: [SearchHit].self) { group in
            for site in sites {
                group.addTask {
                    guard let items = try? await VodService.search(site: site, keyword: query) else { return [] }
                    return items.map { SearchHit(siteKey: site.key, item: $0) }
                }
            }
            for await batch in group {
                hits.append(contentsOf: batch)
            }
        }

        var seen = Set<String>()
        return hits.filter { seen.insert($0.id).inserted }
    }

    /// 直接拿到按片名聚合后的结果
    static func groups(sites: [Site], keyword: String) async -> [TitleGroup] {
        let hits = await search(sites: sites, keyword: keyword)
        return TitleGrouper.groups(from: hits)
    }
}
