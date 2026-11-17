import Foundation

/// 出厂内置的站点目录，首次启动自动导入，与用户订阅共存。
/// - 前 10 条：实测稳定的苹果 CMS 直链源（聚合搜索主力）
/// - 中间 9 条：LunaTV 精简订阅转换而来，全部实测有 m3u8/mp4 直链
/// - 最后 2 条：iBox 平台目录（片库大，但播放地址是平台网页，定位「找片」）
enum BuiltInCatalog {
    static let sites: [Site] = [
        // MARK: 主力直链源
        cms("quantum",    "量子资源",   "https://cj.lziapi.com"),
        cms("modu",       "魔都资源",   "https://www.mdzyapi.com"),
        cms("baofeng",    "暴风资源",   "https://bfzyapi.com"),
        cms("shandian",   "闪电资源",   "https://suoniapi.com"),
        cms("feifan",     "非凡资源",   "https://cj.ffzyapi.com"),
        cms("jinying",    "金鹰资源",   "https://jyzyapi.com"),
        cms("guangsu",    "光速资源",   "https://api.guangsuapi.com"),
        cms("jisu",       "极速资源",   "https://jszyapi.com"),
        cms("zuida",      "最大资源",   "https://api.zuidapi.com"),
        cms("wujin",      "无尽资源",   "https://api.wujinapi.me"),

        // MARK: LunaTV 转换源
        cms("maotai",     "茅台资源",   "https://caiji.maotaizy.cc"),
        cms("dytt",       "电影天堂",   "http://caiji.dyttzyapi.com"),
        cms("maoyan",     "猫眼资源",   "https://api.maoyanapi.top"),
        cms("zy360",      "360 资源",   "https://360zyzz.com"),
        cms("xinlang",    "新浪资源",   "https://api.xinlangapi.com/xinlangapi.php"),
        cms("subo",       "速播资源",   "https://subocaiji.com"),
        cms("uku",        "U酷影视",    "https://api.ukuapi88.com"),
        cms("moduanime",  "魔都动漫",   "https://caiji.moduapi.cc"),
        cms("haohua",     "豪华资源",   "https://hhzyapi.com"),

        // MARK: iBox 平台目录（找片用，播放地址多为平台网页）
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
        ),
    ]

    /// 苹果 CMS 标准接口：域名 + /api.php/provide/vod
    private static func cms(_ key: String, _ name: String, _ base: String) -> Site {
        Site(
            key: key,
            name: name,
            type: 1,
            api: base + "/api.php/provide/vod",
            searchable: true,
            quickSearch: true,
            ext: "",
            playerType: ""
        )
    }

    // MARK: 出厂内置直播源（2026-11 实测）
    // ① zbds：560 频道 12 分组，央视/卫视主力抽样 7/12 可播，综合最优
    // ② Guovin iptv-api：仓库每日自动测速筛选，1616 频道，走 jsdelivr 加速
    // ③ 有魂直播：7000+ 频道含港澳台/体育/电影轮播，量大当备用仓
    static let lives: [LiveSource] = [
        LiveSource(name: "精选直播 · 央视卫视", url: "https://live.zbds.top/tv/iptv4.txt", epg: ""),
        LiveSource(name: "聚合直播 · 每日精选", url: "https://cdn.jsdelivr.net/gh/Guovin/iptv-api@gd/output/result.m3u", epg: ""),
        LiveSource(name: "海量直播 · 备用仓", url: "https://www.iyouhun.com/tv/zb", epg: ""),
    ]
}
