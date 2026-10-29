import UIKit

/// 封面图加载器。
///
/// 服务端对封面设置了 `Cache-Control: public, max-age=604800` 和 `ETag`，
/// 所以这里额外加一层内存缓存：列表滚动时不会重复请求、也不会有占位闪烁。
///
/// 注意：`/history` 里的 `has_cover` 并不可靠 —— 实测有些记录标着 false，
/// 但 `/cover` 依然能取到图（服务端会按 ISBN 再找一遍）。
/// 因此调用方不应拿 `has_cover` 决定要不要请求，这里也不做这种假设。
actor CoverImageLoader {
    static let shared = CoverImageLoader()

    private let memory = NSCache<NSURL, UIImage>()
    /// 已知没有封面的 URL，避免每次滚动都重新撞一次 404。
    private let misses = NSCache<NSURL, NSNumber>()
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
        memory.totalCostLimit = 64 * 1024 * 1024
        misses.countLimit = 500
    }

    func image(for url: URL) async -> UIImage? {
        let key = url as NSURL

        if let cached = memory.object(forKey: key) {
            return cached
        }
        if misses.object(forKey: key) != nil {
            return nil
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
                // 失败时服务端返回 JSON，靠真实解码过滤掉。
                return UIImage(data: data)
            } catch {
                return nil
            }
        }

        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil

        if let result {
            let cost = result.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            memory.setObject(result, forKey: key, cost: cost)
        } else {
            misses.setObject(NSNumber(value: 1), forKey: key)
        }
        return result
    }
}
