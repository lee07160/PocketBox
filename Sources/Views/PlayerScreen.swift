import AVFAudio
import AVKit
import SwiftUI
import WebKit

enum PlaybackRouter {
    /// 能否直接用 AVPlayer 播（HLS / MP4）
    static func isDirect(_ urlString: String) -> Bool {
        let lower = urlString.lowercased()
        if lower.contains(".m3u8") || lower.contains(".mp4") || lower.contains(".mov") {
            return true
        }
        // 有的接口把扩展名藏在 query 里（...?url=xxx.m3u8&t=1）
        if let query = URL(string: urlString)?.query?.lowercased() {
            return query.contains(".m3u8") || query.contains(".mp4")
        }
        return false
    }

    static func parseURL(parse: Parse, video: String) -> URL? {
        let base = parse.url.trimmed()
        let encoded = video.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? video
        return URL(string: base + encoded)
    }
}

/// 嗅探器：非直链地址（分享页 / 跳转页）里往往藏着真正的 m3u8/mp4，
/// 拉一次页面把流媒体地址抠出来，能省掉整条网页解析链路。
enum PlaySniffer {
    /// 绝对地址：https://xxx/index.m3u8?sign=...
    static let streamPattern = try! NSRegularExpression(
        pattern: #"https?://[^\s"'<>\\]+?\.(?:m3u8|mp4)(?:\?[^\s"'<>\\]*)?"#,
        options: [.caseInsensitive]
    )

    /// 相对地址：不少站点写成 const url = "/20230103/xxx/index.m3u8?sign=..."
    static let relativePattern = try! NSRegularExpression(
        pattern: #"["'](/[^"'\s<>\\]+?\.(?:m3u8|mp4)(?:\?[^"'\s<>\\]*)?)["']"#,
        options: [.caseInsensitive]
    )

    /// 返回嗅探到的直链；失败返回 nil
    static func sniff(_ urlString: String) async -> String? {
        let normalized = IDN.normalize(urlString) ?? urlString
        guard let url = URL(string: normalized) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.2 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await Net.session.data(for: request)
            // 有些短链直接 302 到 m3u8，最终 URL 就是结果
            if let final = response.url?.absoluteString, PlaybackRouter.isDirect(final) {
                return final
            }
            // 有些采集站页面是 GBK 编码
            let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
            guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: gb) else {
                return nil
            }
            // JSON 里常见的转义斜杠先还原
            let text = raw.replacingOccurrences(of: "\\/", with: "/")

            if let absolute = firstMatch(streamPattern, in: text) {
                return absolute
            }
            if let relative = firstMatch(relativePattern, in: text, group: 1),
               let base = response.url,
               let resolved = URL(string: relative, relativeTo: base) {
                return resolved.absoluteString
            }
            return nil
        } catch {
            return nil
        }
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String, group: Int = 0) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > group,
              let swiftRange = Range(match.range(at: group), in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }
}

struct PlayerScreen: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let target: PlayTarget

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            content

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white.opacity(0.9), .black.opacity(0.45))
                    .padding(14)
            }
        }
        .onAppear { Self.activateAudioSession() }
    }

    /// 声明为正式媒体播放会话：
    /// 默认会话遵循 iPhone 侧边静音开关（静音键一拨，画面在放、声音没了）
    /// 设为 .playback 后无论静音键状态如何都出声，走扬声器/耳机/蓝牙
    static func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)
    }

    @ViewBuilder
    private var content: some View {
        if PlaybackRouter.isDirect(target.url), let url = URL(string: target.url) {
            NativePlayerView(url: url)
                .ignoresSafeArea()
        } else {
            SniffingPlayer(urlString: target.url, parses: state.parses)
                .ignoresSafeArea()
        }
    }
}

/// 非直链地址的解析链路：嗅探 → 网页解析器 → 报错提示
struct SniffingPlayer: View {
    let urlString: String
    let parses: [Parse]

    @State private var phase: Phase = .sniffing
    @State private var sniffedURL: URL?

    enum Phase { case sniffing, playing, webview, page, failed }

    var body: some View {
        switch phase {
        case .sniffing:
            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.white)
                Text("正在获取播放地址…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await resolve() }
        case .playing:
            if let url = sniffedURL {
                NativePlayerView(url: url)
            }
        case .webview:
            if let parse = parses.first,
               let webURL = PlaybackRouter.parseURL(parse: parse, video: urlString) {
                WebPlayerView(url: webURL)
            } else {
                failureView
            }
        case .page:
            // 兜底：把原页面直接丢进 WebView，很多站点的播放页自带播放器
            if let pageURL = URL(string: IDN.normalize(urlString) ?? urlString) {
                WebPlayerView(url: pageURL)
            } else {
                failureView
            }
        case .failed:
            failureView
        }
    }

    private var failureView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("这个地址需要网页解析")
                .font(.headline)
            Text("已尝试嗅探和全部解析器都无法取出直链。\n可以换个线路或换一集试试。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resolve() async {
        // 1) 嗅探：页面/重定向里找真实直链
        if let found = await PlaySniffer.sniff(urlString), let url = URL(string: found) {
            sniffedURL = url
            phase = .playing
            return
        }
        // 2) 兜底：接口自带解析器则走网页解析，没有就直开原页面
        phase = parses.isEmpty ? .page : .webview
    }
}

struct WebPlayerView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.2 Mobile/15E148 Safari/604.1"
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
