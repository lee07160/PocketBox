import SwiftUI

enum LibraryTab: String, CaseIterable, Identifiable {
    case favorites
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorites: return "收藏"
        case .history: return "历史"
        case .settings: return "设置"
        }
    }
}

struct LibraryView: View {
    @State private var tab: LibraryTab = .favorites

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(LibraryTab.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 8)

                switch tab {
                case .favorites:
                    FavoritesView()
                case .history:
                    HistoryView()
                case .settings:
                    SettingsView()
                }
            }
            .navigationTitle("我的")
            .pocketDestinations()
        }
    }
}

// MARK: - 收藏

struct FavoritesView: View {
    @EnvironmentObject private var state: AppState

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        if state.favorites.isEmpty {
            EmptyHint(title: "还没有收藏", message: "在影片详情页右上角点一下小心心，就会出现在这里")
        } else {
            ScrollView {
                HStack {
                    Text("\(state.favorites.count) 部")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(state.favorites) { record in
                        NavigationLink(value: Route.detail(siteKey: record.siteKey, item: record.item)) {
                            favoriteCard(record)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                state.toggleFavorite(
                                    siteKey: record.siteKey,
                                    siteName: record.siteName,
                                    item: record.item
                                )
                            } label: {
                                Label("取消收藏", systemImage: "heart.slash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private func favoriteCard(_ record: FavoriteRecord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            RemoteImage(urlString: record.item.pic)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )

            Text(record.item.name)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(record.siteName.isEmpty ? record.siteKey : record.siteName)
                .font(.system(size: 10))
                .foregroundStyle(.orange.opacity(0.75))
                .lineLimit(1)
        }
    }
}

// MARK: - 播放历史

struct HistoryView: View {
    @EnvironmentObject private var state: AppState
    @State private var playTarget: PlayTarget?
    @State private var showClearConfirm = false

    var body: some View {
        Group {
            if state.history.isEmpty {
                EmptyHint(title: "还没有播放记录", message: "播过的片子会自动记在这里，下次点一下就能接着看")
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("最近 \(state.history.count) 条")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showClearConfirm = true
                        } label: {
                            Text("清空")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)

                    List {
                        ForEach(state.history) { record in
                            Button {
                                resume(record)
                            } label: {
                                historyRow(record)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    state.removeHistory(record)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .fullScreenCover(item: $playTarget) { target in
            PlayerScreen(target: target).environmentObject(state)
        }
        .confirmationDialog("清空全部播放记录？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) { state.clearHistory() }
            Button("取消", role: .cancel) {}
        }
    }

    private func historyRow(_ record: HistoryRecord) -> some View {
        HStack(spacing: 12) {
            PosterImage(urlString: record.pic, width: 54, height: 76)

            VStack(alignment: .leading, spacing: 5) {
                Text(record.vodName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("\(record.episodeName) · \(record.timeText)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ProgressView(value: record.progress)
                    .tint(.orange)
                    .scaleEffect(x: 1, y: 0.7, anchor: .center)

                HStack(spacing: 6) {
                    Text(record.siteName.isEmpty ? record.siteKey : record.siteName)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange.opacity(0.75))
                    Spacer(minLength: 0)
                    Text(record.updatedText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Image(systemName: "play.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.orange.opacity(0.9))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func resume(_ record: HistoryRecord) {
        playTarget = PlayTarget(
            url: record.url,
            title: record.episodeName,
            siteKey: record.siteKey,
            siteName: record.siteName,
            vodId: record.vodId,
            vodName: record.vodName,
            pic: record.pic,
            startAt: record.isFinished ? 0 : record.position
        )
    }
}
