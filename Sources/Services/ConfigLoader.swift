import Foundation

struct LoadedConfig {
    var sites: [Site] = []
    var parses: [Parse] = []
    var lives: [LiveSource] = []
    var warehouses: [Warehouse] = []

    var isEmpty: Bool { sites.isEmpty && parses.isEmpty && lives.isEmpty && warehouses.isEmpty }
}

enum ConfigLoader {
    /// 从网络拉取接口 JSON
    static func load(urlString: String) async throws -> LoadedConfig {
        let data = try await Net.fetch(urlString)
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> LoadedConfig {
        let raw = try? JSONSerialization.jsonObject(with: data)
        guard let root = raw as? [String: Any] else { throw NetError.decode }
        return parse(root: root)
    }

    static func parse(root: [String: Any]) -> LoadedConfig {
        var config = LoadedConfig()

        if let rows = root["sites"] as? [[String: Any]] {
            config.sites = rows.compactMap { dict in
                let api = JSONValue.string(dict["api"]).trimmed()
                let key = JSONValue.string(dict["key"]).trimmed()
                guard !api.isEmpty else { return nil }
                let name = JSONValue.string(dict["name"]).trimmed()
                return Site(
                    key: key.isEmpty ? api : key,
                    name: name.isEmpty ? (key.isEmpty ? api : key) : name,
                    type: JSONValue.int(dict["type"], fallback: 1),
                    api: api,
                    searchable: JSONValue.bool(dict["searchable"], fallback: true),
                    quickSearch: JSONValue.bool(dict["quickSearch"], fallback: true),
                    ext: JSONValue.string(dict["ext"]),
                    playerType: JSONValue.string(dict["playerType"])
                )
            }
        }

        if let rows = root["parses"] as? [[String: Any]] {
            config.parses = rows.compactMap { dict in
                let url = JSONValue.string(dict["url"]).trimmed()
                guard !url.isEmpty, url.isHTTPURL else { return nil }
                let name = JSONValue.string(dict["name"]).trimmed()
                return Parse(
                    name: name.isEmpty ? "解析" : name,
                    type: JSONValue.int(dict["type"], fallback: 1),
                    url: url
                )
            }
        }

        if let rows = root["lives"] as? [[String: Any]] {
            config.lives = rows.compactMap { dict in
                let url = JSONValue.string(dict["url"]).trimmed()
                guard !url.isEmpty else { return nil }
                let name = JSONValue.string(dict["name"]).trimmed()
                return LiveSource(
                    name: name.isEmpty ? "直播源" : name,
                    url: url,
                    epg: JSONValue.string(dict["epg"]).trimmed()
                )
            }
        }

        if let rows = root["urls"] as? [[String: Any]] {
            config.warehouses = rows.compactMap { dict in
                let url = JSONValue.string(dict["url"]).trimmed()
                guard !url.isEmpty else { return nil }
                let name = JSONValue.string(dict["name"]).trimmed()
                return Warehouse(name: name.isEmpty ? url : name, url: url)
            }
        }

        return config
    }
}
