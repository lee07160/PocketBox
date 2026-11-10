# 口袋盒 PocketBox

iOS 16+ 的 TVBox 轻量客户端，原生 SwiftUI + AVPlayer 实现，支持自行导入 JSON 接口。
第一版**只支持苹果CMS（MacCMS V10）标准 JSON 站点**，不加载 jar / dex 插件。

## 为什么是"轻量版"

安卓 TVBox 的站源分几种 `type`：

| type | 含义 | 本版支持 |
|---|---|---|
| 0 | CMS XML 接口 | ❌ |
| 1 | CMS JSON 接口（苹果CMS V10） | ✅ |
| 3 | jar / dex 蜘蛛插件 | ❌ 需要内嵌 JVM + DEX 解释器 |
| 4 | drpy / T4 服务端源 | ✅ 免嗅探播放 |

`type: 4`（drpy 服务端）是吃下"空壳 + jar"这类纯蜘蛛接口的正解：蜘蛛在服务端跑，iPhone 端只收 JSON 和直链。

大部分采集站都是 `type: 1`，所以跳过插件不影响"能看"，只是少了些特殊站点。

## 功能

- 导入 TVBox 格式 JSON 接口：支持单仓、多仓（多仓会先让你选线路）、直接粘贴 JSON
- 站点浏览：分类 → 列表 → 详情，列表自动翻页
- 多线路切换、选集播放
- 跨站点聚合搜索（并发请求所有 `searchable` 站点，结果边到边显示）
- 直播：解析 m3u（`group-title` 分组）与 txt（`频道名,#genre#` 分组）两种格式
- 播放：HLS/MP4 走原生 AVPlayer（支持画中画、AirPlay）；非直链地址自动套用接口自带的解析器在 WKWebView 里打开
- 收藏、订阅管理、失效保护（刷新失败不会清空已有数据）

## 目录结构

```
project.yml                  XcodeGen 工程描述（部署目标 iOS 16.0）
Sources/App/                 入口 + 全局状态（含本地 JSON 持久化）
Sources/Models/              配置模型、内容模型
Sources/Services/            网络、接口解析、直播解析
Sources/Views/               各个页面 + 播放器
.github/workflows/build.yml  macOS 上自动编译并打包 IPA
```

## 构建（不需要 Mac）

1. 新建一个 GitHub 仓库，把 `PocketBox` 目录里的内容推上去
2. 推到 `main` 会自动跑 Actions，产物在 **Actions → build-ipa → Artifacts → PocketBox-ipa**
3. 想直接拿链接给手机装：打个 tag（如 `v1.0.0`）再推，IPA 会挂到 Release 资源里

```bash
git init
git add .
git commit -m "init"
git remote add origin git@github.com:<你的账号>/PocketBox.git
git push -u origin main
git tag v1.0.0 && git push origin v1.0.0
```

构建流程是 `xcodegen generate` → `xcodebuild` 无签名编译 → 打包 `Payload/` → ad-hoc 签名 → 压缩成 `.ipa`。

## 安装（iOS 16.2 + TrollStore）

三种任选：

1. **TrollStore 直接装**：把 IPA 传到手机（AirDrop 或本地 HTTP），在 TrollStore 里打开它
2. **从 URL 装**：TrollStore → 右上角 `+` → `Install from URL`，填 GitHub Release 里 IPA 的直链
3. **Filza**：IPA 存到 `/var/mobile/Documents/`，在 Filza 里点开选 TrollStore 打开

TrollStore 用的是 CoreTrust 永久签名，装完不会过期，不需要 Apple ID，也不用重新签。

## 使用

1. 打开 App → 首页右上角 `+`
2. 粘贴接口地址（形如 `https://xxx/config.json`），导入
3. 首页出现站点列表 → 点进去 → 选分类 → 点封面 → 选线路 → 选集

多仓接口（带 `urls` 字段）导入后会先列出仓库，选一条再加载。

## 已知限制

- 不支持 jar/dex 插件站点（`type: 3`）
- 不支持 CMS XML 接口（`type: 0`）
- 播放完全依赖系统解码能力，`flv` / `rmvb` / 部分 `mkv` 播不了。需要的话后续接 KSPlayer（FFmpeg）
- 没有 EPG、没有弹幕、没有倍速手势
- 解析器统一用接口 `parses` 里的第一个，且只按 `地址 + 编码后的视频链接` 拼接，不处理更复杂的解析类型

## 实测：嗷呜（英格里希嗷呜.top）接口

2026-11-10 实测结论，作为"真实源"的基准样本：

| 接口 | 状态 |
|---|---|
| `http://www.英格里希嗷呜.top/tv`（主接口） | **已失效**：302 跳到一张占位图（任何 UA 都一样） |
| `https://9763.kstore.vip/aowu.json`（备用一） | ✅ 存活，15KB 配置 |
| `wwww.2525666.xyz/tv`、`饭太硬.cc`、`王二小` | DNS 解析失败 |

备用一的关键数据：**80 个站点 100% 都是 `type: 3`**（蜘蛛插件），没有一个是 CMS JSON；`parses` 也是蜘蛛型；`spider` 指向伪装成 PNG 的 jar（实测 magic `PK`，内含 `classes.dex` + 一个加密的 `assets/woshinidie.bin`，dex 里有 `DexClassLoader` —— 真正的蜘蛛代码是运行时解密动态加载的）。

**这意味着：** 这类"空壳 + jar"接口在 iOS 本地没有任何办法直接跑。要支持它只有两条现实路径：

1. **旁路蜘蛛服务（推荐，已适配）**：在任意设备跑 [drpy](https://github.com/hjdhnx/dr_py) 服务端，把蜘蛛结果转成标准 JSON HTTP 接口，PocketBox 直接吃。见下节。
2. **逆向改写**：把 jar 解密反编译后改写成 Swift/JS —— 加密 + 动态加载 + 运行时拼类名，成本极高且 jar 一更新就废。

## 对接 drpy 服务端（跑蜘蛛）

在电脑 / NAS / 云服务器上部署：

```bash
docker run -itd --name drpy -p 5705:5705 \
  -v /your/path/drpy:/root/drpy \
  hjdhnx/drpy:latest
```

（Windows 直接跑也可以，项目有 `windows搭建教程`；ARM 设备用 `dockerfile_arm64.txt`。）

浏览器打开 `http://服务器IP:5705/index` 管理源，然后在 PocketBox 里添加接口：

```
http://服务器IP:5705/config/0
```

- `mode=0` 局域网地址 / `mode=2` 公网地址；设置了 `JS0_PASSWORD` 的话加 `?pwd=密码`
- 返回的是标准 TVBox JSON，站点 `type=4`，`api` 形如 `http://IP:5705/vod?pwd=x&rule=源名`
- PocketBox 的完整链路：分类/列表/搜索直接调 `/vod`；**播放时把播放页地址经 `play_url=` 参数交回服务端，服务端免嗅探后 302 给 m3u8 直链，AVPlayer 直接播**
- 直播源由 drpy 的 `/lives` 路由给出，TXT 格式，App 已支持

手机和服务器不在同一网络时，记得在服务器防火墙放行 5705 端口；公网暴露建议设置密码。

本工程已为此做了通用兼容：
- **中文域名 punycode 转码**（`IDN.swift`，对拍 RFC 3492 参考实现）
- **UA 可配置**（`Net.userAgent`，默认 `okhttp/3.12.0`，绕过按 UA 分流的服务器）
- **失效报错人话化**：返回网页/占位图时给出明确提示，而不是笼统的"解析失败"
- 导入时直接告知"多少个站点可播"，全插件源会当场提示

## 合规提醒

这个项目只是播放器：不内置、不分发任何内容源，不提供接口市场。接口地址由使用者自行提供，内容合法性由源站和使用者负责。公开分发含盗版影视聚合的客户端在国内有刑事风险（侵犯著作权、非法经营），请自行评估。
