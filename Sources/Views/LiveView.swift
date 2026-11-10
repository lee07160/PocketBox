import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            List {
                if state.lives.isEmpty {
                    EmptyHint(
                        title: "没有直播源",
                        message: "接口里的 lives 字段是空的，导入一个带直播的接口就能看了"
                    )
                    .frame(height: 280)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(state.lives) { source in
                        NavigationLink {
                            LiveGroupListView(source: source)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.name)
                                    .font(.system(size: 15, weight: .medium))
                                Text(source.url)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("直播")
        }
    }
}

struct LiveGroupListView: View {
    let source: LiveSource

    @State private var groups: [LiveGroup] = []
    @State private var loading = false
    @State private var errorBox: ErrorBox?
    @State private var playTarget: PlayTarget?

    var body: some View {
        Group {
            if loading && groups.isEmpty {
                ProgressView()
            } else if groups.isEmpty {
                Text("这个直播源解析不出频道，可能已经失效")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(groups) { group in
                        NavigationLink {
                            ChannelListView(group: group) { channel in
                                playTarget = PlayTarget(url: channel.url, title: channel.name)
                            }
                        } label: {
                            HStack {
                                Text(group.name)
                                Spacer()
                                Text("\(group.channels.count)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fullScreenCover(item: $playTarget) { target in
            PlayerScreen(target: target)
        }
        .alert(item: $errorBox) { box in
            Alert(title: Text("加载失败"), message: Text(box.message), dismissButton: .default(Text("好")))
        }
    }

    private func load() async {
        guard groups.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            groups = try await LiveParser.load(urlString: source.url)
        } catch {
            errorBox = ErrorBox(message: error.localizedDescription)
        }
    }
}

struct ChannelListView: View {
    let group: LiveGroup
    let onPlay: (LiveChannel) -> Void

    var body: some View {
        List {
            ForEach(group.channels) { channel in
                Button {
                    onPlay(channel)
                } label: {
                    HStack {
                        Text(channel.name)
                            .font(.system(size: 14))
                        Spacer()
                        Image(systemName: "play.circle")
                            .foregroundStyle(.orange)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
