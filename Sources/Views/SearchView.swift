import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var state: AppState
    @State private var keyword = ""
    @State private var hits: [SearchHit] = []
    @State private var searching = false
    @State private var searched = false
    @AppStorage("search.groupByTitle") private var groupByTitle = true

    private var groups: [TitleGroup] { TitleGrouper.groups(from: hits) }

    var body: some View {
        NavigationStack {
            List {
                if !hits.isEmpty {
                    Section {
                        Toggle(isOn: $groupByTitle) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("按片名归类")
                                    .font(.system(size: 14))
                                Text(groupByTitle
                                     ? "\(hits.count) 条结果合成 \(groups.count) 部片，进去再选播放源"
                                     : "\(hits.count) 条结果，按站点平铺列出")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.orange)
                    }
                }

                if hits.isEmpty && !searching && searched {
                    Text("没有搜到结果，换个关键词或换站点试试")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if groupByTitle {
                    ForEach(groups) { group in
                        NavigationLink(value: Route.aggregate(hits: group.hits)) {
                            groupRow(group)
                        }
                    }
                } else {
                    ForEach(hits) { hit in
                        NavigationLink(value: Route.detail(siteKey: hit.siteKey, item: hit.item)) {
                            hitRow(siteName: state.site(withKey: hit.siteKey)?.name ?? hit.siteKey, item: hit.item)
                        }
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

    // MARK: - 行样式

    private func groupRow(_ group: TitleGroup) -> some View {
        let item = group.primary.item
        return HStack(spacing: 12) {
            PosterImage(urlString: item.pic, width: 54, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                Text(item.subtitle.isEmpty ? item.remarks : item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(group.sourceCount) 个源")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.orange)
                    if group.maxEpisodeCount > 0 {
                        Text("最全 \(group.maxEpisodeCount) 集")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func hitRow(siteName: String, item: VodItem) -> some View {
        HStack(spacing: 12) {
            PosterImage(urlString: item.pic, width: 54, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                Text(item.subtitle.isEmpty ? item.remarks : item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(siteName)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange.opacity(0.8))
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 搜索

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

        // 去重，同一个站点里同一条目只留一次
        var seen = Set<String>()
        hits = hits.filter { seen.insert($0.id).inserted }
        searching = false
    }
}
