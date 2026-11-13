import Foundation

// MARK: - 订阅配置模型

/// 站点（对应 TVBox 接口 JSON 里的 sites 项）
struct Site: Codable, Identifiable, Hashable {
    var key: String
    var name: String
    var type: Int
    var api: String
    var searchable: Bool
    var quickSearch: Bool
    var ext: String
    var playerType: String

    var id: String { key }

    /// T4 / drpy 服务端源：api 是一个完整的 HTTP 地址
    var isT4: Bool { type == 4 && api.isHTTPURL }

    /// type 1 = CMS JSON；type 4 = T4/drpy 服务端
    var isSupported: Bool { (type == 1 && !api.isEmpty) || isT4 }

    /// 播放是否需要服务端二次解析（把播放页地址换直链）
    var needsPlayResolve: Bool { isT4 }

    var host: String {
        guard let url = URL(string: api), let h = url.host else { return "" }
        return h
    }
}

/// 解析器（对应 parses）
struct Parse: Codable, Identifiable, Hashable {
    var name: String
    var type: Int
    var url: String

    var id: String { name + "|" + url }
}

/// 直播源（对应 lives）
struct LiveSource: Codable, Identifiable, Hashable {
    var name: String
    var url: String
    var epg: String

    var id: String { name + "|" + url }
}

/// 多仓（对应 urls）
struct Warehouse: Codable, Identifiable, Hashable {
    var name: String
    var url: String

    var id: String { url }
}

// MARK: - 内容模型

struct Category: Codable, Identifiable, Hashable {
    var id: String
    var name: String
}

struct Episode: Codable, Identifiable, Hashable {
    var name: String
    var url: String

    var id: String { name + "|" + url }
}

/// 一条播放线路（对应 vod_play_from 里的一个 flag）
struct PlayGroup: Codable, Identifiable, Hashable {
    var name: String
    var episodes: [Episode]

    var id: String { name }
}

struct VodItem: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var pic: String
    var remarks: String
    var year: String
    var area: String
    var typeName: String
    var actor: String
    var director: String
    var content: String
    var groups: [PlayGroup]

    init(
        id: String,
        name: String = "",
        pic: String = "",
        remarks: String = "",
        year: String = "",
        area: String = "",
        typeName: String = "",
        actor: String = "",
        director: String = "",
        content: String = "",
        groups: [PlayGroup] = []
    ) {
        self.id = id
        self.name = name
        self.pic = pic
        self.remarks = remarks
        self.year = year
        self.area = area
        self.typeName = typeName
        self.actor = actor
        self.director = director
        self.content = content
        self.groups = groups
    }

    var subtitle: String {
        [year, area, typeName].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - 直播模型

struct LiveChannel: Codable, Identifiable, Hashable {
    var name: String
    var url: String
    var group: String

    var id: String { group + "|" + name + "|" + url }
}

struct LiveGroup: Codable, Identifiable, Hashable {
    var name: String
    var channels: [LiveChannel]

    var id: String { name }
}

// MARK: - 本地记录

struct FavoriteRecord: Codable, Identifiable, Hashable {
    var siteKey: String
    var siteName: String
    var item: VodItem

    var id: String { siteKey + "|" + item.id }
}

/// 一条播放历史：按「站点 + 影片 + 集」唯一，重复播放会更新进度
struct HistoryRecord: Codable, Identifiable, Hashable {
    var siteKey: String
    var siteName: String
    var vodId: String
    var vodName: String
    var pic: String
    var episodeName: String
    /// 实际点播的地址（续播时还会走一遍嗅探/解析链路）
    var url: String
    var position: Double
    var duration: Double
    var updatedAt: Date

    var id: String { siteKey + "|" + vodId + "|" + episodeName }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    var isFinished: Bool {
        duration > 0 && position / duration > 0.95
    }

    var timeText: String {
        let total = Int(max(position, 0).rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    var updatedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }
}

// MARK: - 播放目标

/// 播放器内用的轻量集信息（选集 / 上下集切换 / 自动连播）
struct PlayEpisode: Hashable {
    var name: String
    var url: String
}

struct PlayTarget: Identifiable, Hashable {
    var id = UUID()
    var url: String
    var title: String
    /// 以下用于写播放历史 / 续播，缺省也不影响直接播放
    var siteKey: String = ""
    var siteName: String = ""
    var vodId: String = ""
    var vodName: String = ""
    var pic: String = ""
    /// 从历史续播时的起播秒数
    var startAt: Double = 0
    /// 当前线路的整季集列表，为空表示单集播放（无选集/上下集）
    var episodes: [PlayEpisode] = []
    /// 当前集在 episodes 里的下标
    var episodeIndex: Int = 0

    var hasHistoryContext: Bool {
        !siteKey.isEmpty && !vodId.isEmpty && !vodName.isEmpty
    }

    var hasNextEpisode: Bool { episodeIndex + 1 < episodes.count }
    var hasPrevEpisode: Bool { episodeIndex > 0 && episodeIndex < episodes.count }
}

// MARK: - 错误展示

struct ErrorBox: Identifiable {
    var id = UUID()
    var message: String
}
