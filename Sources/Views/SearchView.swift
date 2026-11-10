import SwiftUI

struct SearchHit: Identifiable, Hashable {
    var siteKey: String
    var item: VodItem

    var id: String { siteKey + "|" + item.id }
}

struct SearchView: View {
    @EnvironmentObject private var state: AppState
    @State private var keyword = ""
    @State private var hits: [SearchHit] = []
    @State private var searching = false
    @State private var searched = false

    var body: some View {
        NavigationStack {
            List {
                if hits.isEmpty && !searching && searched {
                    Text("没有搜到结果，换个关键词或换站点试试")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(hits) { hit in
                    NavigationLink(value: Route.detail(siteKey: hit.siteKey, item: hit.item)) {
                        HStack(spacing: 12) {
                            PosterImage(urlString: hit.item.pic, width: 54, height: 76)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(hit.item.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .lineLimit(2)
                                Text(hit.item.subtitle.isEmpty ? hit.item.remarks : hit.item.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(state.site(withKey: hit.siteKey)?.name ?? hit.siteKey)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange.opacity(0.8))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("搜索")
            .pocketDestinations()
            .searchable(text: $keyword, prompt: "片名 / 演员")
            .onSubmit(of: .search) {
                Task { await runSearch() }
            }
            .overlay {
                if searching {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("正在 \(state.searchableSites.count) 个站点里搜索…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func runSearch() async {
        let query = keyword.trimmed()
        guard !query.isEmpty else { return }
        searching = true
        searched = true
        hits = []

        let sites = state.searchableSites
        await withTaskGroup(of: [SearchHit].self) { group in
            for site in sites {
                group.addTask {
                    guard let items = try? await VodService.search(site: site, keyword: query) else { return [] }
                    return items.map { SearchHit(siteKey: site.key, item: $0) }
                }
            }
            for await batch in group {
                hits.append(contentsOf: batch)
            }
        }

        // 去重，同一个站点里同名同 ID 的只留一条
        var seen = Set<String>()
        hits = hits.filter { seen.insert($0.id).inserted }
        searching = false
    }
}
