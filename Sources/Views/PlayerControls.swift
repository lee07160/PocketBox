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
    enum Kind { case brightness, volume }
    var kind: Kind
    var value: Double
}

struct PlayHUDView: View {
    let hud: PlayHUD

    private var iconName: String {
        switch hud.kind {
        case .brightness:
            if hud.value < 0.34 { return "sun.min.fill" }
            if hud.value < 0.7 { return "sun.max.fill" }
            return "sun.max.fill"
        case .volume:
            if hud.value <= 0.001 { return "speaker.slash.fill" }
            if hud.value < 0.5 { return "speaker.wave.1.fill" }
            return "speaker.wave.3.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 96, height: 6)
                Capsule()
                    .fill(Color.white)
                    .frame(width: 96 * CGFloat(hud.value), height: 6)
            }

            Text("\(Int((hud.value * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .frame(width: 38, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.6), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
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

    func load(_ url: URL) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        finished = false
        player.play()
        isPlaying = true
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

    @StateObject private var model = PlayerModel()

    @State private var fillScreen = false
    @State private var landscape = false
    @State private var controlsVisible = true
    @State private var hud: PlayHUD?
    @State private var hudTask: Task<Void, Never>?
    @State private var hideTask: Task<Void, Never>?
    @State private var dragBaseline: Double?
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var originalBrightness: CGFloat = UIScreen.main.brightness

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoSurface(player: model.player, fill: fillScreen)
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
            model.load(url)
            scheduleHide()
        }
        .onDisappear {
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

    // MARK: 手势层

    private var gestureLayer: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in handleDrag(value, size: geo.size) }
                        .onEnded { _ in
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
        let onLeftSide = value.startLocation.x < size.width / 2

        if dragBaseline == nil {
            dragBaseline = onLeftSide
                ? Double(UIScreen.main.brightness)
                : Double(SystemVolume.shared.value)
        }
        guard let baseline = dragBaseline else { return }

        // 高度 65% 的滑动量对应 0 → 100%
        let span = max(size.height * 0.65, 1)
        let delta = -value.translation.height / span
        let target = min(max(baseline + Double(delta), 0), 1)

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
            Spacer(minLength: 0)

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

    private var bottomBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
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
        fillScreen = landscape
        Orientation.apply(landscape: landscape)
        scheduleHide()
    }

    private func timeText(_ seconds: Double) -> String {
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
