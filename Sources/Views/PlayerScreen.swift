import AVKit
import SwiftUI
import WebKit

enum PlaybackRouter {
    /// 能否直接用 AVPlayer 播（HLS / MP4）
    static func isDirect(_ urlString: String) -> Bool {
        let lower = urlString.lowercased()
        return lower.contains(".m3u8") || lower.contains(".mp4") || lower.contains(".mov")
    }

    static func parseURL(parse: Parse, video: String) -> URL? {
        let base = parse.url.trimmed()
        let encoded = video.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? video
        return URL(string: base + encoded)
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
    }

    @ViewBuilder
    private var content: some View {
        if PlaybackRouter.isDirect(target.url), let url = URL(string: target.url) {
            VideoPlayerView(url: url)
                .ignoresSafeArea()
        } else if let parse = state.parses.first, let url = PlaybackRouter.parseURL(parse: parse, video: target.url) {
            WebPlayerView(url: url)
                .ignoresSafeArea()
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
                Text("这个地址需要网页解析")
                    .font(.headline)
                Text("接口里没有可用的解析器，或者这条线路不是直链。\n可以换个线路试试。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.updatesNowPlayingInfoCenter = true
        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
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
