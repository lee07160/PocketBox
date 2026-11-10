import Foundation
import SwiftUI

struct Subscription: Codable, Identifiable, Hashable {
    var name: String
    var url: String

    var id: String { url }
}

final class AppState: ObservableObject {
    @Published private(set) var subscriptions: [Subscription] = []
    @Published private(set) var sites: [Site] = []
    @Published private(set) var parses: [Parse] = []
    @Published private(set) var lives: [LiveSource] = []
    @Published private(set) var warehouses: [Warehouse] = []
    @Published private(set) var favorites: [FavoriteRecord] = []
    @Published private(set) var history: [HistoryRecord] = []
    @Published var isLoading = false
    @Published var toast: String?

    private let storeURL: URL = {
        let manager = FileManager.default
        let directory = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("pocketbox-state.json")
    }()

    init() {
        restore()
    }

    var supportedSites: [Site] { sites.filter { $0.isSupported } }
    var searchableSites: [Site] { supportedSites.filter { $0.searchable || $0.quickSearch } }

    func site(withKey key: String) -> Site? {
        sites.first { $0.key == key }
    }

    // MARK: - 订阅

    func addSubscription(urlString: String) async {
        let raw = urlString.trimmed()
        guard !raw.isEmpty else { return }

        // 支持一次粘贴多行/空格/逗号分隔的多个接口地址
        if !raw.hasPrefix("{") {
            let tokens = raw
                .split(whereSeparator: { $0.isNewline || $0 == "," || $0 == "，" || $0 == " " || $0 == "\t" })
                .map { String($0).trimmed() }
                .filter { !$0.isEmpty }
            if tokens.count > 1, tokens.allSatisfy({ $0.isHTTPURL }) {
                isLoading = true
                var totalSites = 0, totalSupported = 0, totalLives = 0, failed = 0
                for token in tokens {
                    if let result = await importOne(raw: token) {
                        totalSites += result.sites
                        totalSupported += result.supported
                        totalLives += result.lives
                    } else {
                        failed += 1
                    }
                }
                isLoading = false
                var parts = ["已导入 \(tokens.count - failed)/\(tokens.count) 个接口"]
                if totalSites > 0 { parts.append("\(totalSites) 个站点（\(totalSupported) 个可直接播放）") }
                if totalLives > 0 { parts.append("\(totalLives) 个直播源") }
                toast = parts.joined(separator: "，")
                return
            }
        }

        isLoading = true
        defer { isLoading = false }

        guard let result = await importOne(raw: raw) else { return }

        if result.isWarehouse {
            return
        }
        if result.sites == 0 {
            toast = "已导入 \(result.lives) 个直播源"
        } else if result.supported == 0 {
            toast = "接口里 \(result.sites) 个站点全是 jar 插件源（type 3），当前版本不支持，需要服务端方案，详见 README"
        } else {
            toast = "已导入 \(result.sites) 个站点，其中 \(result.supported) 个可直接播放"
        }
    }

    private struct ImportResult {
        var sites: Int
        var supported: Int
        var lives: Int
        var isWarehouse: Bool = false
    }

    /// 导入单个接口；失败时已写好 toast，返回 nil
    private func importOne(raw: String) async -> ImportResult? {
        do {
            let config: LoadedConfig
            if raw.hasPrefix("{") {
                config = try ConfigLoader.parse(data: Data(raw.utf8))
            } else {
                config = try await ConfigLoader.load(urlString: raw)
            }

            // 多仓：先让用户选具体线路
            if !config.warehouses.isEmpty && config.sites.isEmpty {
                warehouses = config.warehouses
                return ImportResult(sites: 0, supported: 0, lives: 0, isWarehouse: true)
            }

            guard !config.isEmpty else {
                toast = "这个接口里没有可用内容"
                return nil
            }

            merge(config)
            if raw.isHTTPURL {
                let name = config.sites.first?.name ?? "订阅"
                let subscription = Subscription(name: name, url: raw)
                if !subscriptions.contains(where: { $0.id == subscription.id }) {
                    subscriptions.append(subscription)
                }
            }
            save()
            return ImportResult(
                sites: config.sites.count,
                supported: config.sites.filter { $0.isSupported }.count,
                lives: config.lives.count
            )
        } catch {
            toast = "导入失败：\(error.localizedDescription)"
            return nil
        }
    }

    func chooseWarehouse(_ warehouse: Warehouse) async {
        warehouses = []
        await addSubscription(urlString: warehouse.url)
    }

    // MARK: - 平台目录源（iBox 同款）

    /// 两条苹果 CMS 标准接口，来自 iBox 内置的那套「平台聚合采集」。
    /// 特点：片库极大（合计约 40 万条、更新到当天），但播放地址基本都是
    /// 腾讯/爱奇艺/优酷/芒果/B 站的**网页地址**，要解析服务才能出直链。
    /// 所以定位成「找片目录」：能搜、能看简介，点播建议切到直链源。
    static let platformCatalogSites: [Site] = [
        Site(
            key: "ibox-catalog-a",
            name: "iBox目录A · 影视",
            type: 1,
            api: "http://38.76.166.26:7788/api.php/provide/vod/",
            searchable: true,
            quickSearch: true,
            ext: "",
            playerType: ""
        ),
        Site(
            key: "ibox-catalog-b",
            name: "iBox目录B · 剧集",
            type: 1,
            api: "http://149.104.6.155:12121/api.php/provide/vod/",
            searchable: true,
            quickSearch: true,
            ext: "",
            playerType: ""
        )
    ]

    /// 添加平台目录源，返回实际新增条数（0 表示已经有了）
    @discardableResult
    func addPlatformCatalog() -> Int {
        var added = 0
        for site in Self.platformCatalogSites {
            let exists = sites.contains { $0.key == site.key || $0.api == site.api }
            guard !exists else { continue }
            sites.append(site)
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    func refreshAll() async {
        guard !subscriptions.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        for subscription in subscriptions {
            if let config = try? await ConfigLoader.load(urlString: subscription.url) {
                merge(config)
            }
        }
        save()
    }

    func removeSubscription(_ subscription: Subscription) {
        subscriptions.removeAll { $0.id == subscription.id }
        save()
    }

    func clearAll() {
        subscriptions = []
        sites = []
        parses = []
        lives = []
        favorites = []
        history = []
        warehouses = []
        save()
    }

    // MARK: - 收藏

    func toggleFavorite(siteKey: String, siteName: String, item: VodItem) {
        if let index = favorites.firstIndex(where: { $0.siteKey == siteKey && $0.item.id == item.id }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(FavoriteRecord(siteKey: siteKey, siteName: siteName, item: item), at: 0)
        }
        save()
    }

    func isFavorite(siteKey: String, itemId: String) -> Bool {
        favorites.contains { $0.siteKey == siteKey && $0.item.id == itemId }
    }

    var favoriteItems: [FavoriteRecord] { favorites }

    // MARK: - 播放历史

    /// 记录/更新一条播放历史（同一集只保留一条，进度取最新）
    func recordHistory(_ record: HistoryRecord) {
        var entry = record
        entry.updatedAt = Date()
        history.removeAll { $0.id == entry.id }
        history.insert(entry, at: 0)
        if history.count > 120 {
            history = Array(history.prefix(120))
        }
        save()
    }

    func removeHistory(_ record: HistoryRecord) {
        history.removeAll { $0.id == record.id }
        save()
    }

    func clearHistory() {
        guard !history.isEmpty else { return }
        history = []
        save()
    }

    /// 同一部片最近看过哪一集
    func lastEpisode(siteKey: String, vodId: String) -> HistoryRecord? {
        history.first { $0.siteKey == siteKey && $0.vodId == vodId }
    }

    // MARK: - 合并与持久化

    private func merge(_ config: LoadedConfig) {
        for site in config.sites where !sites.contains(where: { $0.key == site.key && $0.api == site.api }) {
            sites.append(site)
        }
        for parse in config.parses where !parses.contains(where: { $0.url == parse.url }) {
            parses.append(parse)
        }
        for live in config.lives where !lives.contains(where: { $0.url == live.url }) {
            lives.append(live)
        }
    }

    private struct Snapshot: Codable {
        var subscriptions: [Subscription] = []
        var sites: [Site] = []
        var parses: [Parse] = []
        var lives: [LiveSource] = []
        var favorites: [FavoriteRecord] = []
        /// 老版本的存档没有这个字段，用 Optional 保证能解出来
        var history: [HistoryRecord]?
    }

    private func save() {
        let snapshot = Snapshot(
            subscriptions: subscriptions,
            sites: sites,
            parses: parses,
            lives: lives,
            favorites: favorites,
            history: history
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func restore() {
        guard let data = try? Data(contentsOf: storeURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        subscriptions = snapshot.subscriptions
        sites = snapshot.sites
        parses = snapshot.parses
        lives = snapshot.lives
        favorites = snapshot.favorites
        history = snapshot.history ?? []
    }
}
