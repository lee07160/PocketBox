import SwiftUI
import UIKit

/// 带自定义请求头 + 内存缓存的图片加载器
/// AsyncImage 不能加 header，豆瓣图床不带 Referer 会返回 418，所以自己实现一套
@MainActor
final class RemoteImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var failed = false

    static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    private var currentKey: String?

    func load(urlString: String, referer: String?) {
        let key = (referer ?? "-") + "|" + urlString
        if currentKey == key, image != nil { return }
        currentKey = key

        if let cached = Self.cache.object(forKey: key as NSString) {
            image = cached
            failed = false
            return
        }

        guard let normalized = IDN.normalize(urlString),
              let url = URL(string: normalized),
              urlString.isHTTPURL else {
            failed = true
            return
        }

        image = nil
        failed = false

        var request = URLRequest(url: url)
        request.setValue(Net.browserUA, forHTTPHeaderField: "User-Agent")
        if let referer, !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        request.timeoutInterval = 20

        Task { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200...399).contains(http.statusCode),
                      let decoded = UIImage(data: data) else {
                    self?.failed = true
                    return
                }
                Self.cache.setObject(decoded, forKey: key as NSString)
                self?.image = decoded
            } catch {
                self?.failed = true
            }
        }
    }
}

struct RemoteImage: View {
    let urlString: String
    var referer: String? = nil
    var contentMode: ContentMode = .fill
    var placeholderIcon: String = "film"

    @StateObject private var loader = RemoteImageLoader()

    var body: some View {
        ZStack {
            Color.clear
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .clipped()
        .task(id: urlString) {
            await loader.load(urlString: urlString, referer: referer)
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.white.opacity(0.06)
            if !loader.failed {
                Image(systemName: placeholderIcon)
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
    }
}
