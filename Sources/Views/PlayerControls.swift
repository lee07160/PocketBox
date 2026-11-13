import AVFoundation
import AVKit
import MediaPlayer
import SwiftUI
import UIKit

// MARK: - 视频渲染层

/// 用 AVPlayerLayer 直接渲染，方便叠加自定义手势与控制层
final class PlayerLayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    let fill: Bool

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let view = PlayerLayerUIView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        let gravity: AVLayerVideoGravity = fill ? .resizeAspectFill : .resizeAspect
        if uiView.playerLayer.videoGravity != gravity {
            uiView.playerLayer.videoGravity = gravity
        }
    }
}

// MARK: - 系统音量

/// iOS 没有公开的音量设置 API，业界做法是把 MPVolumeView 藏进视图层级里操作它的 UISlider
final class SystemVolume {
    static let shared = SystemVolume()

    private let volumeView = MPVolumeView(frame: CGRect(x: -200, y: -200, width: 44, height: 44))
    private var slider: UISlider? {
        volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    var value: Float {
        if let slider { return slider.value }
        return AVAudioSession.sharedInstance().outputVolume
    }

    func set(_ newValue: Float) {
        let clamped = min(max(newValue, 0), 1)
        guard let slider else { return }
        DispatchQueue.main.async {
            slider.value = clamped
        }
    }

    func hostView() -> MPVolumeView {
        volumeView.showsRouteButton = false
        volumeView.showsVolumeSlider = true
        return volumeView
    }
}

/// 把音量滑块挂进视图层级（必须存在于 UI 里才生效），视觉上几乎不可见
struct VolumeHost: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = .clear
        let host = SystemVolume.shared.hostView()
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.widthAnchor.constraint(equalToConstant: 44),
            host.heightAnchor.constraint(equalToConstant: 44)
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - 方向控制

enum Orientation {
    static func apply(landscape: Bool) {
        let mask: UIInterfaceOrientationMask = landscape ? .landscapeRight : .portrait
        if #available(iOS 16.0, *) {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            guard let scene else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        } else {
            let value = landscape ? UIInterfaceOrientation.landscapeRight.rawValue
                                  : UIInterfaceOrientation.portrait.rawValue
            UIDevice.current.setValue(value, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}

// MARK: - 手势提示条

struct PlayHUD: Equatable {
    enum Kind: Equatable {
        case brightness, volume
        /// 水平滑动快进/快退预览（forward = 向后快进）
        case seek(forward: Bool)
    }
    var kind: Kind
    var value: Double
    /// seek 模式下的目标时间（秒）
    var seekSeconds: Double = 0
}

struct PlayHUDView: View {
    let hud: PlayHUD

    private var iconName: String {
        switch hud.kind {
        case .brightness:
            return "sun.max.fill"
        case .volume:
            if hud.value <= 0.001 { return "speaker.slash.fill" }
            if hud.value < 0.5 { return "speaker.wave.1.fill" }
            return "speaker.wave.3.fill"
        case .seek(let forward):
            return forward ? "goforward.15" : "gobackward.15"
        }
    }

    /// seek 模式显示目标时间，其余显示百分比
    private var valueText: String {
        if case .seek = hud.kind {
            return Self.timeText(hud.seekSeconds)
        }
        return "\(Int((hud.value * 100).rounded()))%"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18)

            if case .seek = hud.kind {
                Text(valueText)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            } else {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 96, height: 6)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 96 * CGFloat(hud.value), height: 6)
                }

                Text(valueText)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .frame(width: 38, alignment: .leading)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.6), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
    }

    static func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - 播放状态

final class PlayerModel: ObservableObject {
    let player = AVPlayer()
    @Published var isPlaying = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var finished = false

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init() {
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.4, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            if seconds.isFinite { self.position = seconds }
            if let itemDuration = self.player.currentItem?.duration.seconds,
               itemDuration.isFinite, itemDuration > 0 {
                self.duration = itemDuration
            }
            self.isPlaying = self.player.rate > 0
        }
    }

    func load(_ url: URL, startAt: Double = 0) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        finished = false
        player.play()
        isPlaying = true
        if startAt > 1 {
            player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.finished = true }
        }
    }

    func togglePlay() {
        if finished {
            finished = false
            player.seek(to: .zero)
            player.play()
            return
        }
        if player.rate > 0 {
            player.pause()
        } else {
            player.play()
        }
    }

    func endScrub(at seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}

// MARK: - 原生播放器（自定义控制层 + 手势）

struct NativePlayerView: View {
    let url: URL
    var startAt: Double = 0
    /// 播放进度回调（每约 15 秒 + 退出时各一次），用于写播放历史
    var onProgress: ((Double, Double) -> Void)? = nil
    /// 播放地址确定后回调（嗅探出的直链），可用于更新历史里的可复用地址
    var onResolved: ((String) -> Void)? = nil
    /// 集信息：episodeCount > 1 时显示上一集/下一集与跳过片尾
    var episodeIndex: Int = 0
    var episodeCount: Int = 1
    var onPrev: (() -> Void)? = nil
    /// 播下一集（跳过片尾按钮 / 自动连播共用）
    var onNext: (() -> Void)? = nil
    /// 关闭播放器（× 跟随控制层显隐）
    var onClose: (() -> Void)? = nil
    /// 打开选集面板（底部控制条「选集」文字按钮）
    var onPickEpisode: (() -> Void)? = nil

    /// 片头一般 60~90 秒，固定跳到 90s；片尾临近结尾 90s 内出按钮
    private static let introSeconds = 90.0
    private static let outroSeconds = 90.0

    @StateObject private var model = PlayerModel()

    // 画面缩放恒为「等比完整显示」(aspectFit)：全屏只旋转方向，不改缩放——
    // 之前全屏切 aspectFill 会把画面放大裁边，看起来"超出屏幕"
    @State private var landscape = false
    @State private var controlsVisible = true
    @State private var hud: PlayHUD?
    @State private var hudTask: Task<Void, Never>?
    @State private var hideTask: Task<Void, Never>?
    @State private var dragBaseline: Double?
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var originalBrightness: CGFloat = UIScreen.main.brightness
    // 水平滑动 = 快进/快退：本次拖动是否为 seek 模式、起点位置、当前目标位置
    @State private var dragIsSeek = false
    @State private var seekBaseline: Double = 0
    @State private var seekTarget: Double = 0
    /// 水平滑满整个屏幕宽度对应的快进/快退秒数
    private static let seekSpanSeconds: Double = 90

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoSurface(player: model.player, fill: false)
                .ignoresSafeArea()

            gestureLayer

            if controlsVisible {
                controlOverlay
                    .transition(.opacity)
            }

            if let hud {
                PlayHUDView(hud: hud)
                    .transition(.opacity)
            }

            // 音量控制需要 MPVolumeView 真实存在于层级中
            VolumeHost()
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
        }
        .statusBarHidden(true)
        .onAppear {
            PlayerScreen.activateAudioSession()
            originalBrightness = UIScreen.main.brightness
            model.load(url, startAt: startAt)
            onResolved?(url.absoluteString)
            scheduleHide()
        }
        .onChange(of: progressBucket) { _ in
            onProgress?(model.position, model.duration)
        }
        .onChange(of: model.finished) { done in
            // 自动连播：播完且还有下一集时自动切（无下一集则保留重播按钮）
            guard done, let onNext, episodeIndex + 1 < episodeCount else { return }
            onNext()
        }
        .onDisappear {
            onProgress?(model.position, model.duration)
            model.stop()
            hudTask?.cancel()
            hideTask?.cancel()
            UIScreen.main.brightness = originalBrightness
            if landscape {
                landscape = false
                Orientation.apply(landscape: false)
            }
        }
    }

    /// 每 15 秒一个刻度，避免每 0.4 秒都写一次历史
    private var progressBucket: Int {
        Int(max(model.position, 0) / 15)
    }

    // MARK: 手势层

    private var gestureLayer: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in handleDrag(value, size: geo.size) }
                        .onEnded { _ in
                            if dragIsSeek {
                                // 松手才真正跳转，滑动过程中只显示预览时间
                                if model.duration > 0 {
                                    model.endScrub(at: seekTarget)
                                }
                                dragIsSeek = false
                            }
                            dragBaseline = nil
                            scheduleHUDHide()
                            if controlsVisible { scheduleHide() }
                        }
                )
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.18)) {
                        controlsVisible.toggle()
                    }
                    if controlsVisible { scheduleHide() } else { hideTask?.cancel() }
                }
        }
        .ignoresSafeArea()
    }

    private func handleDrag(_ value: DragGesture.Value, size: CGSize) {
        // 第一次移动时判定方向并锁定：水平 = 快进/快退，竖直 = 亮度/音量
        if dragBaseline == nil {
            dragIsSeek = abs(value.translation.width) > abs(value.translation.height)
            if dragIsSeek {
                seekBaseline = model.position
                dragBaseline = 0
            } else {
                let onLeftSide = value.startLocation.x < size.width / 2
                dragBaseline = onLeftSide
                    ? Double(UIScreen.main.brightness)
                    : Double(SystemVolume.shared.value)
            }
        }

        if dragIsSeek {
            guard model.duration > 0 else { return }
            let ratio = value.translation.width / max(size.width, 1)
            let target = min(max(seekBaseline + ratio * Self.seekSpanSeconds, 0), model.duration)
            seekTarget = target
            hud = PlayHUD(
                kind: .seek(forward: target >= seekBaseline),
                value: 0,
                seekSeconds: target
            )
            scheduleHUDHide()
            return
        }

        guard let baseline = dragBaseline else { return }

        // 高度 65% 的滑动量对应 0 → 100%
        let span = max(size.height * 0.65, 1)
        let delta = -value.translation.height / span
        let target = min(max(baseline + Double(delta), 0), 1)

        let onLeftSide = value.startLocation.x < size.width / 2
        if onLeftSide {
            UIScreen.main.brightness = CGFloat(target)
            hud = PlayHUD(kind: .brightness, value: target)
        } else {
            SystemVolume.shared.set(Float(target))
            hud = PlayHUD(kind: .volume, value: target)
        }
        scheduleHUDHide()
    }

    private func scheduleHUDHide() {
        hudTask?.cancel()
        hudTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { hud = nil }
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            if model.isPlaying {
                withAnimation(.easeOut(duration: 0.25)) { controlsVisible = false }
            }
        }
    }

    // MARK: 控制层

    private var controlOverlay: some View {
        VStack(spacing: 0) {
            // 顶部：关闭 ×（跟随控制层显隐）
            HStack {
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white.opacity(0.9), .black.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)

            Spacer(minLength: 0)

            // 跳过片头 / 跳过片尾（条件显示）
            skipButtons
                .padding(.bottom, 14)

            Button {
                model.togglePlay()
                scheduleHide()
            } label: {
                Image(systemName: model.finished ? "arrow.counterclockwise.circle.fill" : (model.isPlaying ? "pause.circle.fill" : "play.circle.fill"))
                    .font(.system(size: 54))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white.opacity(0.95), .black.opacity(0.35))
                    .shadow(radius: 8)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            bottomBar
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    // MARK: 跳过片头 / 片尾

    /// 片头区间（前 90 秒）显示「跳过片头」
    private var showSkipIntro: Bool {
        !scrubbing
            && model.position > 3
            && model.position < Self.introSeconds
            && model.duration > Self.introSeconds * 2.5
    }

    /// 临近结尾（剩 90 秒内）且还有下一集时显示「跳过片尾」
    private var showSkipOutro: Bool {
        !scrubbing
            && model.duration > 300
            && model.position > 3
            && model.duration - model.position < Self.outroSeconds
            && episodeIndex + 1 < episodeCount
            && !model.finished
    }

    @ViewBuilder
    private var skipButtons: some View {
        if showSkipIntro {
            Button {
                model.endScrub(at: Self.introSeconds)
                scheduleHide()
            } label: {
                Label("跳过片头", systemImage: "forward.end.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        } else if showSkipOutro {
            Button {
                onNext?()
            } label: {
                Label("跳过片尾", systemImage: "forward.end.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                // 上一集 / 下一集（多集时显示）
                if episodeCount > 1 {
                    Button {
                        onPrev?()
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(episodeIndex > 0 ? .white : .white.opacity(0.3))
                            .frame(width: 30, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(episodeIndex == 0)
                    .accessibilityLabel("上一集")
                }

                Text(timeText(scrubbing ? scrubValue : model.position))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)

                Slider(
                    value: Binding(
                        get: { scrubbing ? scrubValue : model.position },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...max(model.duration, 0.1)
                ) { editing in
                    if editing {
                        scrubbing = true
                        scrubValue = model.position
                        hideTask?.cancel()
                    } else {
                        model.endScrub(at: scrubValue)
                        scrubbing = false
                        scheduleHide()
                    }
                }
                .tint(.white)

                Text(timeText(model.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))

                if episodeCount > 1 {
                    Button {
                        onNext?()
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(episodeIndex + 1 < episodeCount ? .white : .white.opacity(0.3))
                            .frame(width: 30, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(episodeIndex + 1 >= episodeCount)
                    .accessibilityLabel("下一集")
                }

                // 选集入口：多集时显示，放在全屏键旁边
                if episodeCount > 1, let onPickEpisode {
                    Button(action: onPickEpisode) {
                        Text("选集")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选集")
                }

                Button {
                    toggleFullscreen()
                } label: {
                    Image(systemName: landscape
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func toggleFullscreen() {
        landscape.toggle()
        Orientation.apply(landscape: landscape)
        scheduleHide()
    }

    private func timeText(_ seconds: Double) -> String {
        PlayHUDView.timeText(seconds)
    }
}
