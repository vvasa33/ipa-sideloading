import Foundation

struct MemoryStat: Decodable, Equatable {
    var total: Double
    var used: Double
    var percent: Double
}

struct MachineStats: Decodable, Equatable {
    var hostname: String
    var cpuPercent: Double
    var perCore: [Double]
    var loadAvg: [Double]
    var mem: MemoryStat
    var swap: MemoryStat
    var cpuTemp: Double?
    var disk: MemoryStat
    var netRxBps: Double
    var netTxBps: Double
    var uptimeS: Double
}

@MainActor
final class StatsStore: ObservableObject {
    @Published var stats: MachineStats?
    @Published var lastUpdate: Date?
    @Published var isOffline = false
    @Published var hasAttempted = false

    private let settings: AppSettings
    private let session: URLSession

    init(settings: AppSettings) {
        self.settings = settings
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.5
        config.timeoutIntervalForResource = 3
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    func run() async {
        guard !Runtime.isPreview else { return }
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    func refresh() async {
        guard let url = settings.statsURL else {
            stats = nil
            isOffline = false
            hasAttempted = false
            lastUpdate = nil
            return
        }
        hasAttempted = true
        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                isOffline = true
                return
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            stats = try decoder.decode(MachineStats.self, from: data)
            lastUpdate = Date()
            isOffline = false
        } catch {
            isOffline = true
        }
    }
}
