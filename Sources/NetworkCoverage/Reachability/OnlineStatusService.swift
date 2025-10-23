import Foundation

protocol OnlineStatusService {
    func online() -> AsyncStream<Bool>
}
