import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var state: AppState
    let siteKey: String
    let item: VodItem

    @State private var detail: VodItem?
    @State private var selectedGroup = 0
    @State private var playTarget: PlayTarget?
    @State private var resolving: Episode?
    @State private var loading = false
    @State private var errorBox: ErrorBox?

    private var current: VodItem { detail ?? item }
    private var site: Site? { state.site(withKey: siteKey) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                resumeRow
                if !current.content.isEmpty {
                    Text(current.content)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineSpacing(4)
                }
                episodeSection
            }
            .padding(16)
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    state.toggleFavorite(siteKey: siteKey, siteName: site?.name ?? "", item: current)
                } label: {
                    Image(systemName: state.isFavorite(siteKey: siteKey, itemId: current.id) ? "heart.fill" : "heart")
                        .foregroundStyle(.orange)
                }
            }
        }
        .task { await loadDetail() }
        .overlay {
            if resolving != nil {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("正在向服务端要直链…")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .fullScreenCover(item: $playTarget) { target in
            PlayerScreen(target: target)
                .environmentObject(state)
        }
        .alert(item: $errorBox) { box in
            Alert(title: Text("播放失败"), message: Text(box.message), dismissButton: .default(Text("好")))
        }
    }

    @ViewBuilder
    private var resumeRow: some View {
        let record = state.lastEpisode(siteKey: siteKey, vodId: current.id)
        let episode = record.flatMap { item in
            current.groups.flatMap { $0.episodes }.first { $0.name == item.episodeName }
        }
        if let record, let episode {
            Button {
                play(episode, startAt: record.isFinished ? 0 : record.position)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Color.orange, in: Circle())
                        .foregroundStyle(.black)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("继续观看 \(record.episodeName)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                        Text("上次看到 \(record.timeText)")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            PosterImage(urlString: current.pic, width: 110, height: 156)

            VStack(alignment: .leading, spacing: 8) {
                Text(current.name)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(3)

                if !current.subtitle.isEmpty {
                    Text(current.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if !current.remarks.isEmpty {
                    Text(current.remarks)
                        .font(.system(size: 11))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(.orange)
                }

                if !current.actor.isEmpty {
                    Text("主演：" + current.actor)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var episodeSection: some View {
        if current.groups.isEmpty {
            if loading {
                HStack { ProgressView(); Text("正在加载线路…").font(.footnote).foregroundStyle(.secondary) }
            } else {
                Text("这个条目没有可播放的线路")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(current.groups.enumerated()), id: \.element.id) { index, group in
                            Button {
                                selectedGroup = index
                            } label: {
                                Text(group.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedGroup == index ? Color.orange : Color.white.opacity(0.08),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(selectedGroup == index ? Color.black : Color.white.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

                let group = current.groups[min(selectedGroup, current.groups.count - 1)]
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(group.episodes) { episode in
                        Button {
                            play(episode)
                        } label: {
                            Text(episode.name)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func loadDetail() async {
        guard !loading, current.groups.isEmpty, let site else { return }
        loading = true
        defer { loading = false }
        do {
            if let full = try await VodService.detail(site: site, id: item.id) {
                detail = full
            }
        } catch {
            errorBox = ErrorBox(message: error.localizedDescription)
        }
    }

    private func play(_ episode: Episode, startAt: Double = 0) {
        guard let site else { return }
        if site.needsPlayResolve {
            // T4/drpy 服务端源：先换直链再播
            resolving = episode
            Task {
                defer { resolving = nil }
                do {
                    let resolved = try await Type4Service.resolve(site: site, episodeURL: episode.url)
                    playTarget = makeTarget(url: resolved.url.absoluteString, episode: episode, site: site, startAt: startAt)
                } catch {
                    errorBox = ErrorBox(message: error.localizedDescription)
                }
            }
        } else {
            playTarget = makeTarget(url: episode.url, episode: episode, site: site, startAt: startAt)
        }
    }

    /// 带上站点/影片信息与整季集列表，播放时才能写历史、在播放器里切集
    private func makeTarget(url: String, episode: Episode, site: Site, startAt: Double) -> PlayTarget {
        // 找到这一集所属的线路，把整季传给播放器（选集/上下集/自动连播用）
        let group = current.groups.first { g in g.episodes.contains { $0.id == episode.id } }
        let index = group?.episodes.firstIndex { $0.id == episode.id } ?? 0
        return PlayTarget(
            url: url,
            title: episode.name,
            siteKey: siteKey,
            siteName: site.name,
            vodId: current.id,
            vodName: current.name,
            pic: current.pic,
            startAt: startAt,
            episodes: (group?.episodes ?? []).map { PlayEpisode(name: $0.name, url: $0.url) },
            episodeIndex: index
        )
    }
}
