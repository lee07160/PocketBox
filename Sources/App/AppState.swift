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
        isLoading = true
        defer { isLoading = false }

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
                return
            }

            guard !config.isEmpty else {
                toast = "这个接口里没有可用内容"
                return
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
            let supported = config.sites.filter { $0.isSupported }.count
            if config.sites.isEmpty {
                toast = "已导入 \(config.lives.count) 个直播源"
            } else {
                toast = "已导入 \(config.sites.count) 个站点，其中 \(supported) 个可直接播放"
                if supported == 0 {
                    toast = "接口里 \(config.sites.count) 个站点全是 jar 插件源（type 3），当前版本不支持，需要服务端方案，详见 README"
                }
            }
        } catch {
            toast = "导入失败：\(error.localizedDescription)"
        }
    }

    func chooseWarehouse(_ warehouse: Warehouse) async {
        warehouses = []
        await addSubscription(urlString: warehouse.url)
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
    }

    private func save() {
        let snapshot = Snapshot(
            subscriptions: subscriptions,
            sites: sites,
            parses: parses,
            lives: lives,
            favorites: favorites
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
    }
}
