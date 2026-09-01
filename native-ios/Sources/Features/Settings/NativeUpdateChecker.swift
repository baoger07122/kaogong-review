import Foundation

struct NativeReleaseManifest: Codable, Equatable {
    let version: String
    let build: Int
    let releasedAt: String
    let file: String
}

enum NativeUpdateStatus: Equatable {
    case latest(NativeReleaseManifest)
    case available(NativeReleaseManifest)
}

enum NativeUpdateChecker {
    static let manifestURL = URL(
        string: "https://raw.githubusercontent.com/baoger07122/kaogong-review/refs/heads/codex/ios-native-rewrite/downloads/native/latest.json"
    )!

    static func check(currentVersion: String, session: URLSession = .shared) async throws -> NativeUpdateStatus {
        var request = URLRequest(url: manifestURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 12
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        let manifest = try JSONDecoder().decode(NativeReleaseManifest.self, from: data)
        return compare(manifest.version, currentVersion) == .orderedDescending ? .available(manifest) : .latest(manifest)
    }

    private static func compare(_ left: String, _ right: String) -> ComparisonResult {
        let leftParts = left.split(separator: ".").map { Int($0) ?? 0 }
        let rightParts = right.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(leftParts.count, rightParts.count) {
            let lhs = index < leftParts.count ? leftParts[index] : 0
            let rhs = index < rightParts.count ? rightParts[index] : 0
            if lhs < rhs { return .orderedAscending }
            if lhs > rhs { return .orderedDescending }
        }
        return .orderedSame
    }
}
