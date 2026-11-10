import SwiftUI

enum Route: Hashable {
    case site(key: String)
    case category(siteKey: String, categoryId: String, title: String)
    case detail(siteKey: String, item: VodItem)
    case aggregate(hits: [SearchHit])
    case douban(subject: DoubanSubject)
}

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("站点", systemImage: "square.grid.2x2") }

            DoubanView()
                .tabItem { Label("推荐", systemImage: "flame") }

            LiveView()
                .tabItem { Label("直播", systemImage: "tv") }

            SearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(.orange)
    }
}

extension View {
    /// 在每个 NavigationStack 的根视图上挂一次，全栈共用
    func pocketDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .site(let key):
                SiteHomeView(siteKey: key)
            case .category(let siteKey, let categoryId, let title):
                CategoryGridView(siteKey: siteKey, categoryId: categoryId, title: title)
            case .detail(let siteKey, let item):
                DetailView(siteKey: siteKey, item: item)
            case .aggregate(let hits):
                AggregatedDetailView(hits: hits)
            case .douban(let subject):
                DoubanDetailView(subject: subject)
            }
        }
    }
}
