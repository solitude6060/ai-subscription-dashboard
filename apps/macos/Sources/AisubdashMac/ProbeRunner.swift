import Foundation
import AisubdashCore

struct ProbeRunner {
    private let endpoint: UsageEndpoint?

    init?(arguments: [String]) {
        switch arguments.first {
        case "--probe-local":
            endpoint = arguments.count == 1 ? .local : nil
        case "--probe-tailscale":
            endpoint = arguments.count == 2 ? UsageEndpoint(tailscale: arguments[1]) : nil
        default:
            return nil
        }
    }

    func run() async -> Int32 {
        guard let endpoint else {
            fputs("Invalid probe arguments.\n", stderr)
            return 2
        }

        do {
            let client = UsageClient()
            let dashboard = try await client.load(endpoint)
            let providers = dashboard.accounts.count
            let quotas = dashboard.accounts.reduce(0) { $0 + $1.quotas.count }
            print("providers=\(providers) quotas=\(quotas)")
            return 0
        } catch {
            fputs("Probe failed.\n", stderr)
            return 1
        }
    }
}
