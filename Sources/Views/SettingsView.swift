import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingAdd = false
    @State private var showingClearConfirm = false

    var body: some View {
        List {
            Section("订阅接口") {
                if state.subscriptions.isEmpty {
                    Text("还没有订阅")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(state.subscriptions) { subscription in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(subscription.name)
                            .font(.system(size: 14, weight: .medium))
                        Text(subscription.url)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { indexSet in
                    let targets = indexSet.compactMap { index in
                        index < state.subscriptions.count ? state.subscriptions[index] : nil
                    }
                    targets.forEach { state.removeSubscription($0) }
                }
                Button("添加接口") { showingAdd = true }
            }

            Section("当前接口统计") {
                statRow("可用站点", "\(state.supportedSites.count)")
                statRow("全部站点（含不支持的）", "\(state.sites.count)")
                statRow("网页解析器", "\(state.parses.count)")
                statRow("直播源", "\(state.lives.count)")
                statRow("收藏", "\(state.favorites.count)")
                statRow("播放记录", "\(state.history.count)")
            }

            Section("解析器") {
                if state.parses.isEmpty {
                    Text("接口里没有提供 parses")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(state.parses) { parse in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(parse.name).font(.system(size: 13))
                        Text(parse.url)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Section {
                Button("刷新全部订阅") {
                    Task { await state.refreshAll() }
                }
                Button("清空所有数据", role: .destructive) {
                    showingClearConfirm = true
                }
            } footer: {
                Text("支持 type = 1（CMS JSON）与 type = 4（drpy/T4 服务端）站点。drpy 源播放时会先向服务端要直链（免嗅探）。jar 插件站点会被跳过，需要 drpy 服务端方案，见 README。")
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddSubscriptionView()
        }
        .confirmationDialog("确定清空所有接口、收藏和播放记录？", isPresented: $showingClearConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) { state.clearAll() }
            Button("取消", role: .cancel) {}
        }
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
