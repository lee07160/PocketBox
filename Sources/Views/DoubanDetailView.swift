import SwiftUI

/// 豆瓣条目详情：简介 + 自动到所有采集站找片源
struct DoubanDetailView: View {
    @EnvironmentObject private var state: AppState
    let subject: DoubanSubject

    @State private var detail: DoubanAbstract?
    @State private var groups: [TitleGroup] = []
    @State private var searching = false
    @State private var keyword = ""
    @State private var started = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                peopleBlock
                commentBlock
                sourceSection
                searchAgainBlock
            }
            .padding(16)
        }
        .navigationTitle(subject.searchTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !started else { return }
            started = true
            keyword = subject.searchTitle
            Task { await loadDetail() }
            await findSources(subject.searchTitle)
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            RemoteImage(urlString: subject.cover, referer: DoubanService.referer)
                .frame(width: 110, height: 156)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(detail?.title ?? subject.title)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(3)

                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text(rateText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("豆瓣")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                if let subtitle = detail?.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let detail, !detail.episodes.isEmpty {
                    Text("共 \(detail.episodes) 集")
                        .font(.system(size: 11))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var rateText: String {
        if let rate = detail?.rate, !rate.isEmpty { return rate }
        return subject.rate.isEmpty ? "暂无评分" : subject.rate
    }

    @ViewBuilder
    private var peopleBlock: some View {
        if let detail {
            VStack(alignment: .leading, spacing: 6) {
                if !detail.directors.isEmpty {
                    infoLine(title: "导演", value: detail.directors.joined(separator: " / "))
                }
                if !detail.actors.isEmpty {
                    infoLine(title: "主演", value: detail.actors.prefix(6).joined(separator: " / "))
                }
            }
        }
    }

    private func infoLine(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var commentBlock: some View {
        if let comment = detail?.comment, !comment.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("热评")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(comment)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineSpacing(3)
                    .lineLimit(5)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - 片源

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("播放源")
                    .font(.system(size: 13, weight: .semibold))
                Text(searching
                     ? "正在 \(state.searchableSites.count) 个站点里找…"
                     : (groups.isEmpty ? "没找到" : "\(groups.count) 部匹配"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if searching && groups.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在搜索「\(subject.searchTitle)」")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 6)
            } else if groups.isEmpty {
                Text("采集站里暂时没有「\(subject.searchTitle)」，新片可能要等几天才有人上传。下面可以改个关键词再找。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            } else {
                VStack(spacing: 8) {
                    ForEach(groups) { group in
                        NavigationLink(value: Route.aggregate(hits: group.hits)) {
                            sourceRow(group)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sourceRow(_ group: TitleGroup) -> some View {
        HStack(spacing: 12) {
            PosterImage(urlString: group.primary.item.pic, width: 52, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text(group.primary.item.subtitle.isEmpty ? group.primary.item.remarks : group.primary.item.subtitle)
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
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 改词重搜

    private var searchAgainBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("换个关键词再找")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("片名", text: $keyword)
                    .font(.system(size: 13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .submitLabel(.search)
                    .onSubmit { Task { await findSources(keyword) } }

                Button {
                    Task { await findSources(keyword) }
                } label: {
                    Text("搜索")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 数据

    private func loadDetail() async {
        detail = try? await DoubanService.abstract(id: subject.id)
    }

    private func findSources(_ query: String) async {
        let text = query.trimmed()
        guard !text.isEmpty else { return }
        searching = true
        defer { searching = false }
        groups = await Aggregator.groups(sites: state.searchableSites, keyword: text)
    }
}
