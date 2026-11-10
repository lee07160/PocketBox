import SwiftUI

struct DoubanView: View {
    @EnvironmentObject private var state: AppState

    @State private var media: DoubanMedia = .movie
    @State private var board: DoubanBoard = .movieHot
    @State private var subjects: [DoubanSubject] = []
    @State private var cache: [DoubanBoard: [DoubanSubject]] = [:]
    @State private var loadingBoards = Set<DoubanBoard>()
    @State private var errorText: String?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                mediaPicker
                boardBar
                content
            }
            .navigationTitle("豆瓣热榜")
            .pocketDestinations()
            .task { await loadIfNeeded(board) }
            .onChange(of: media) { value in
                let target = DoubanBoard.boards(for: value).first ?? .movieHot
                switchBoard(to: target)
            }
            .onChange(of: board) { value in
                switchBoard(to: value)
            }
        }
    }

    // MARK: - 顶部

    private var mediaPicker: some View {
        Picker("", selection: $media) {
            ForEach(DoubanMedia.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var boardBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DoubanBoard.boards(for: media)) { item in
                    Button {
                        board = item
                    } label: {
                        Text(item.title)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                board == item ? Color.orange : Color.white.opacity(0.08),
                                in: Capsule()
                            )
                            .foregroundStyle(board == item ? Color.black : Color.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - 列表

    @ViewBuilder
    private var content: some View {
        if loading && subjects.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在拉豆瓣榜单…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if subjects.isEmpty, let errorText {
            VStack(spacing: 12) {
                Image(systemName: "flame")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                Button("重试") {
                    Task { await load(board, force: true) }
                }
                .font(.footnote)
                .foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(subjects) { subject in
                        NavigationLink(value: Route.douban(subject)) {
                            DoubanPosterCard(subject: subject)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable { await load(board, force: true) }
        }
    }

    // MARK: - 数据

    private func loadIfNeeded(_ target: DoubanBoard) async {
        if target != board { subjects = cache[target] ?? [] }
        if let cached = cache[target] {
            subjects = cached
            return
        }
        await load(target)
    }

    private func load(_ target: DoubanBoard, force: Bool = false) async {
        if loading { return }
        if !force, let cached = cache[target] {
            subjects = cached
            return
        }
        loading = true
        errorText = nil
        defer { loading = false }

        do {
            let list = try await DoubanService.board(target)
            cache[target] = list
            if target == board {
                subjects = list
            }
        } catch {
            if target == board {
                subjects = []
                errorText = error.localizedDescription
            }
        }
    }
}

// MARK: - 海报卡片

struct DoubanPosterCard: View {
    let subject: DoubanSubject

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            RemoteImage(urlString: subject.cover, referer: DoubanService.referer)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .overlay(alignment: .bottomTrailing) {
                    if subject.rate != "0" && !subject.rate.isEmpty {
                        Text(subject.rate)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.orange)
                            .padding(4)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if !subject.badge.isEmpty {
                        Text(subject.badge)
                            .font(.system(size: 9))
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(4)
                    }
                }

            Text(subject.title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}
