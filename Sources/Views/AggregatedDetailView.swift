import SwiftUI

/// 同一部片、多个站点资源的聚合详情页
/// 上方是片子信息，下面是「播放源」选择器；选定源后再选线路 / 集数播放
struct AggregatedDetailView: View {
    @EnvironmentObject private var state: AppState
    let hits: [SearchHit]

    @State private var selectedSource = 0
    @State private var selectedGroup = 0
    @State private var details: [String: VodItem] = [:]
    @State private var failedSources = Set<String>()
    @State private var loadingDetail = false
    @State private var playTarget: PlayTarget?
    @State private var resolving: Episode?
    @State private var errorBox: ErrorBox?

    private var hit: SearchHit {
        guard !hits.isEmpty else { return SearchHit(siteKey: "", item: VodItem(id: "")) }
        return hits[min(max(selectedSource, 0), hits.count - 1)]
    }
    private var current: VodItem { details[hit.id] ?? hit.item }
    private var site: Site? { state.site(withKey: hit.siteKey) }

    private var headerItem: VodItem {
        if !current.pic.isEmpty { return current }
        return hits.first(where: { !$0.item.pic.isEmpty })?.item ?? current
    }

    /// 同一个片名下出现多个年份 → 说明是同名翻拍，源标签要带年份
    private var hasYearConflict: Bool {
        Set(hits.map { $0.item.year }.filter { !$0.isEmpty }).count > 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                resumeRow
                if !headerItem.content.isEmpty {
                    Text(headerItem.content)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineSpacing(4)
                        .lineLimit(8)
                }
                sourceSection
                episodeSection
            }
            .padding(16)
        }
        .navigationTitle(headerItem.name.isEmpty ? hit.item.name : headerItem.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    state.toggleFavorite(
                        siteKey: hit.siteKey,
                        siteName: state.site(withKey: hit.siteKey)?.name ?? hit.siteKey,
                        item: current
                    )
                } label: {
                    Image(systemName: state.isFavorite(siteKey: hit.siteKey, itemId: current.id) ? "heart.fill" : "heart")
                        .foregroundStyle(.orange)
                }
            }
        }
        .task(id: hit.id) { await loadDetailIfNeeded() }
        .onChange(of: selectedSource) { _ in selectedGroup = 0 }
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
            PlayerScreen(target: target).environmentObject(state)
        }
        .alert(item: $errorBox) { box in
            Alert(title: Text("播放失败"), message: Text(box.message), dismissButton: .default(Text("好")))
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            PosterImage(urlString: headerItem.pic, width: 110, height: 156)

            VStack(alignment: .leading, spacing: 8) {
                Text(headerItem.name)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(3)

                if !headerItem.subtitle.isEmpty {
                    Text(headerItem.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Text("\(hits.count) 个播放源")
                    .font(.system(size: 11))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(.orange)

                if !headerItem.actor.isEmpty {
                    Text("主演：" + headerItem.actor)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 继续观看

    @ViewBuilder
    private var resumeRow: some View {
        let record = state.lastEpisode(siteKey: hit.siteKey, vodId: current.id)
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

    // MARK: - 播放源

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("播放源")
                    .font(.system(size: 13, weight: .semibold))
                Text("选一个源")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(hits.enumerated()), id: \.element.id) { index, item in
                        sourceChip(index: index, hit: item)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func sourceChip(index: Int, hit: SearchHit) -> some View {
        let active = index == selectedSource
        let name = state.site(withKey: hit.siteKey)?.name ?? hit.siteKey
        let loaded = details[hit.id]
        let count = (loaded ?? hit.item).bestEpisodeCount
        let tag: String = {
            let item = loaded ?? hit.item
            let remarks = item.remarks
            let base: String
            if !remarks.isEmpty {
                base = remarks
            } else {
                base = count > 0 ? "\(count)集" : "未知"
            }
            // 同名不同年份（翻拍）时把年份带上，避免选错版本
            if hasYearConflict, !item.year.isEmpty { return item.year + " · " + base }
            return base
        }()

        return Button {
            selectedSource = index
        } label: {
            VStack(spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(tag)
                    .font(.system(size: 9))
                    .opacity(0.75)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(active ? Color.orange : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(active ? Color.black : Color.white.opacity(0.8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 线路 + 选集

    @ViewBuilder
    private var episodeSection: some View {
        let item = current
        if item.groups.isEmpty {
            if loadingDetail {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在加载这个源的线路…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(failedSources.contains(hit.id) ? "这个源没取到可播放的线路，换个源试试" : "这个源没有可播放的线路")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("重试") {
                            failedSources.remove(hit.id)
                            Task { await loadDetailIfNeeded(force: true) }
                        }
                        .font(.footnote)
                        if let next = nextPlayableSource() {
                            Button("试试「\(state.site(withKey: hits[next].siteKey)?.name ?? "下一个源")」") {
                                selectedSource = next
                            }
                            .font(.footnote)
                        }
                    }
                    .foregroundStyle(.orange)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if item.groups.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(item.groups.enumerated()), id: \.element.id) { index, group in
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
                }

                let group = item.groups[min(selectedGroup, item.groups.count - 1)]
                Text("共 \(group.episodes.count) 集 · \(state.site(withKey: hit.siteKey)?.name ?? "")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

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

    // MARK: - 数据

    private func loadDetailIfNeeded(force: Bool = false) async {
        let key = hit.id
        if !force, details[key] != nil { return }
        if !force, hit.item.hasPlayableEpisodes { return }
        guard let site else { return }
        loadingDetail = true
        defer { loadingDetail = false }
        do {
            if let full = try await VodService.detail(site: site, id: hit.item.id) {
                details[key] = full
                if !full.hasPlayableEpisodes { failedSources.insert(key) }
            } else {
                failedSources.insert(key)
            }
        } catch {
            failedSources.insert(key)
            errorBox = ErrorBox(message: error.localizedDescription)
        }
    }

    private func nextPlayableSource() -> Int? {
        guard hits.count > 1 else { return nil }
        for offset in 1..<hits.count {
            let index = (selectedSource + offset) % hits.count
            if hits[index].item.hasPlayableEpisodes { return index }
        }
        return hits.count > 1 ? (selectedSource + 1) % hits.count : nil
    }

    private func play(_ episode: Episode, startAt: Double = 0) {
        guard let site else { return }
        if site.needsPlayResolve {
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

    /// 带上当前选中的源，便于写播放历史 / 从历史续播
    private func makeTarget(url: String, episode: Episode, site: Site, startAt: Double) -> PlayTarget {
        PlayTarget(
            url: url,
            title: episode.name,
            siteKey: hit.siteKey,
            siteName: site.name,
            vodId: current.id,
            vodName: current.name,
            pic: current.pic,
            startAt: startAt
        )
    }
}
