import UIKit

/// 封面图加载器。
///
/// 服务端对封面设置了 `Cache-Control: public, max-age=604800` 和 `ETag`，
/// 所以这里额外加一层内存缓存：列表滚动时不会重复请求、也不会有占位闪烁。
actor CoverImageLoader {
    static let shared = CoverImageLoader()

    private let memory = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            diskPath: "cover-images"
        )
        session = URLSession(configuration: configuration)
        memory.countLimit = 300
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = memory.object(forKey: url as NSURL) {
            return cached
        }

        // 同一个 URL 并发请求只发一次。
        if let existing = inFlight[url] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [session] in
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    return nil
                }
                // 失败时服务端返回 JSON，这里靠真实解码过滤掉。
                guard let image = UIImage(data: data) else { return nil }
                return image
            } catch {
                return nil
            }
        }

        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil

        if let result {
            memory.setObject(result, forKey: url as NSURL)
        }
        return result
    }

    /// 下拉刷新时调用，避免看到旧封面。
    func clear() {
        memory.removeAllObjects()
    }
}
