import SwiftUI

struct SiteHomeView: View {
    @EnvironmentObject private var state: AppState
    let siteKey: String

    @State private var categories: [Category] = []
    @State private var loading = false
    @State private var errorBox: ErrorBox?

    private var site: Site? { state.site(withKey: siteKey) }

    var body: some View {
        Group {
            if let site {
                List {
                    Section {
                        NavigationLink(value: Route.category(siteKey: siteKey, categoryId: "", title: "全部")) {
                            Label("全部内容", systemImage: "square.stack")
                        }
                    }

                    Section("分类") {
                        ForEach(categories) { category in
                            NavigationLink(value: Route.category(siteKey: siteKey, categoryId: category.id, title: category.name)) {
                                Text(category.name)
                            }
                        }
                    }
                }
                .navigationTitle(site.name)
                .navigationBarTitleDisplayMode(.inline)
                .task { await load(site) }
                .overlay {
                    if loading && categories.isEmpty { ProgressView() }
                }
                .alert(item: $errorBox) { box in
                    Alert(title: Text("加载失败"), message: Text(box.message), dismissButton: .default(Text("好")))
                }
            } else {
                EmptyHint(title: "站点不存在", message: "接口可能已经刷新过了")
            }
        }
    }

    private func load(_ site: Site) async {
        guard categories.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            categories = try await VodService.categories(site: site)
        } catch {
            errorBox = ErrorBox(message: error.localizedDescription)
        }
    }
}

struct CategoryGridView: View {
    @EnvironmentObject private var state: AppState
    let siteKey: String
    let categoryId: String
    let title: String

    @State private var items: [VodItem] = []
    @State private var page = 1
    @State private var pageCount = 1
    @State private var loading = false
    @State private var errorBox: ErrorBox?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(items) { item in
                    NavigationLink(value: Route.detail(siteKey: siteKey, item: item)) {
                        VodCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if item.id == items.last?.id {
                            Task { await loadNext() }
                        }
                    }
                }
            }
            .padding(12)

            if loading {
                ProgressView().padding(.bottom, 24)
            }

            if !loading && items.isEmpty {
                Text("这里没有内容，换个分类试试")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 60)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadNext() }
        .alert(item: $errorBox) { box in
            Alert(title: Text("加载失败"), message: Text(box.message), dismissButton: .default(Text("好")))
        }
    }

    private func loadNext() async {
        guard !loading, page <= pageCount, let site = state.site(withKey: siteKey) else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await VodService.list(site: site, categoryId: categoryId, page: page)
            let fresh = result.items.filter { newItem in
                !items.contains { $0.id == newItem.id }
            }
            items.append(contentsOf: fresh)
            pageCount = result.pageCount
            page += 1
        } catch {
            pageCount = 1
            errorBox = ErrorBox(message: error.localizedDescription)
        }
    }
}
