import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                if !state.favorites.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(state.favorites) { record in
                                    NavigationLink(value: Route.detail(siteKey: record.siteKey, item: record.item)) {
                                        FavoriteCard(record: record)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("收藏")
                    }
                }

                Section("站点") {
                    if state.supportedSites.isEmpty {
                        EmptyHint(
                            title: state.sites.isEmpty ? "还没有接口" : "接口里全是插件源",
                            message: state.sites.isEmpty
                                ? "点右上角 + 导入一个 TVBox 格式的 JSON 接口地址"
                                : "这个接口的 \(state.sites.count) 个站点全部依赖 jar 蜘蛛（type 3），本地跑不了，需要服务端方案，详见 README"
                        )
                        .frame(height: 260)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(state.supportedSites) { site in
                            NavigationLink(value: Route.site(key: site.key)) {
                                SiteRow(site: site)
                            }
                        }
                    }
                }
            }
            .navigationTitle("口袋盒")
            .pocketDestinations()
            .refreshable { await state.refreshAll() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddSubscriptionView()
            }
            .overlay {
                if state.isLoading {
                    ProgressView()
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}

struct AddSubscriptionView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("接口地址") {
                    TextField("https://example.com/api.json", text: $text, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...4)
                        .keyboardType(.URL)
                }

                if !state.warehouses.isEmpty {
                    Section("检测到多仓，选择一条线路") {
                        ForEach(state.warehouses) { warehouse in
                            Button(warehouse.name) {
                                Task {
                                    await state.chooseWarehouse(warehouse)
                                    dismiss()
                                }
                            }
                        }
                    }
                }

                Section {
                    Text("支持单仓与多仓链接，也可以直接粘贴 JSON 文本。\n识别 type = 1 的苹果CMS JSON 站点，以及 type = 4 的 drpy/T4 服务端站点（免嗅探播放）。jar 插件站点会被跳过。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("添加接口")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        Task {
                            await state.addSubscription(urlString: text)
                            if state.warehouses.isEmpty { dismiss() }
                        }
                    }
                    .disabled(text.trimmed().isEmpty || state.isLoading)
                }
            }
            .alert("提示", isPresented: toastBinding) {
                Button("好") { state.toast = nil }
            } message: {
                Text(state.toast ?? "")
            }
        }
    }

    private var toastBinding: Binding<Bool> {
        Binding(
            get: { state.toast != nil && state.warehouses.isEmpty },
            set: { if !$0 { state.toast = nil } }
        )
    }
}
