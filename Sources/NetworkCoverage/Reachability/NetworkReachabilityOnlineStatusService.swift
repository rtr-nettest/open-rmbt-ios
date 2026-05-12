import Foundation

struct NetworkReachabilityOnlineStatusService: OnlineStatusService {
    func online() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            var lastEmitted: Bool?
            let emit: (NetworkReachability.NetworkReachabilityStatus) -> Void = { status in
                let isOnline = Self.isOnline(status: status)
                if lastEmitted != isOnline {
                    lastEmitted = isOnline
                    continuation.yield(isOnline)
                }
            }

            Task { @MainActor in
                NetworkReachability.shared.startMonitoring()
                emit(NetworkReachability.shared.status)
                let token = NetworkReachability.shared.addReachabilityCallbackReturningToken(emit)

                continuation.onTermination = { _ in
                    NetworkReachability.shared.removeReachabilityCallback(token)
                }
            }
        }
    }

    static func isOnline(status: NetworkReachability.NetworkReachabilityStatus) -> Bool {
        switch status {
        case .wifi, .mobile: true
        case .notReachability, .unknown: false
        }
    }
}
