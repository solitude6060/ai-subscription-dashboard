import Foundation
import AisubdashCore

enum ProbeRunner {
    static func runIfRequested(arguments: [String]) async -> Int32? {
        guard let first = arguments.first else {
            return nil
        }

        let endpoint: UsageEndpoint
        switch first {
        case "--probe-local":
            guard arguments.count == 1 else {
                fputs("Invalid probe arguments.\n", stderr)
                return 2
            }
            endpoint = .local

        case "--probe-tailscale":
            guard arguments.count == 2, let parsed = UsageEndpoint(tailscale: arguments[1]) else {
                fputs("Invalid Tailscale endpoint URL.\n", stderr)
                return 2
            }
            endpoint = parsed

        default:
            fputs("Unsupported command-line arguments.\n", stderr)
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
