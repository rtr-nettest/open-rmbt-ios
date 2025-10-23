/*****************************************************************************************************
 * Copyright 2014-2016 SPECURE GmbH
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *****************************************************************************************************/

import Foundation
import CocoaAsyncSocket
#if swift(>=3.2)
    import Darwin
#else
    import RMBTClientPrivate
#endif

import Foundation

protocol ControlServerProviding: AnyObject {
    func getSettings(_ success: @escaping EmptyCallback, error failure: @escaping ErrorCallback)
    func getIpv4(success: @escaping IpResponseSuccessCallback, error failure: @escaping (_ error: Error?) -> Void)
    func getIpv6(success: @escaping IpResponseSuccessCallback, error failure: @escaping (_ error: Error?) -> Void)
}


///
public struct IPInfo: CustomStringConvertible {

    ///
    public var connectionAvailable = false

    ///
    public var nat: Bool {

        return internalIp != externalIp
    }

    ///
    public var internalIp: String? = nil

    ///
    public var externalIp: String? = nil

    ///
    public var description: String {
        return "IPInfo: connectionAvailable: \(connectionAvailable), nat: \(nat), internalIp: \(String(describing: internalIp)), externalIp: \(String(describing: externalIp))"
    }
}

///
public struct ConnectivityInfo: CustomStringConvertible {

    ///
    public var ipv4 = IPInfo()

    ///
    public var ipv6 = IPInfo()

    ///
    public var description: String {
        return "ConnectivityInfo: ipv4: \(ipv4), ipv6: \(ipv6)"
    }
}

///
open class ConnectivityService: NSObject { // TODO: rewrite with ControlServerNew

    public typealias ConnectivityInfoCallback = (_ connectivityInfo: ConnectivityInfo) -> ()

    fileprivate let socketQueue = DispatchQueue(label: "ConnectivityService.Queue")
    fileprivate var udpSocket: GCDAsyncUdpSocket?
    
    ///
    var callback: ConnectivityInfoCallback?

    ///
    var connectivityInfo = ConnectivityInfo()

    ///
    var ipv4Finished = true
    private var ipv4InProgress = false

    ///
    var ipv6Finished = true
    private var ipv6InProgress = false
    
    var ipsWasChecked = false
    private let controlServer: ControlServerProviding
    var localIpOverrides: (() -> (ipv4: String?, ipv6: String?))?
    var observedAddressProvider: (() -> [String: (ipv4: String?, ipv6: String?)])?
    private var activeNetworkType: RMBTNetworkType?
    private var checkCounter: Int = 0
    private var activeCheckId: Int = 0
    private var lastCachedNetworkType: RMBTNetworkType?

    public override convenience init() {
        self.init(controlServer: RMBTControlServer.shared)
    }

    init(controlServer: ControlServerProviding) {
        self.controlServer = controlServer
        super.init()
    }

    func updateActiveNetworkType(_ type: RMBTNetworkType?) {
        assert(Thread.isMainThread, "updateActiveNetworkType must be called on the main thread")
        activeNetworkType = type
        log("active network hint updated → \(String(describing: type))")
    }

    deinit {
        if let socket = udpSocket {
            socket.close()
            socket.setDelegate(nil)
        }
        self.callback = nil
    }
    ///
    /// Returns connectivity information. When `refresh` is `false` (default) and the cached result
    /// matches the currently active network type, the callback is invoked immediately with cached data
    /// and no new check is started. Passing `refresh: true` always triggers a fresh check via the control server.
    ///
    /// Calling this method supersedes any in-flight check when a refresh is requested; only the most recent callback is retained.
    ///
    /// - Parameters:
    ///   - refresh: Forces a new control-server check when `true`.
    ///   - callback: Closure invoked with the latest connectivity info.
    open func checkConnectivity(refresh: Bool = false, callback: @escaping ConnectivityInfoCallback) {
        assert(Thread.isMainThread, "checkConnectivity must be called on the main thread")

        let cachedMatchesCurrentNetwork = ipsWasChecked && lastCachedNetworkType == activeNetworkType
        if !refresh, cachedMatchesCurrentNetwork {
            log("serving cached connectivity result (network=\(networkTypeName(activeNetworkType)))")
            callback(connectivityInfo)
            return
        }

        self.callback = callback

        prepareForNewCheck()
        log("starting connectivity check \(activeCheckId) (network=\(networkTypeName(activeNetworkType)))")
        
        resolveLocalIpAddresses()

        checkIPV4()
        checkIPV6()
    }

    private func prepareForNewCheck() {
        checkCounter += 1
        activeCheckId = checkCounter
        ipv4Finished = false
        ipv6Finished = false
        ipv4InProgress = false
        ipv6InProgress = false
        ipsWasChecked = false
        lastCachedNetworkType = nil
        connectivityInfo = ConnectivityInfo()
        log("prepared new check id=\(activeCheckId)")
    }

    private func resolveLocalIpAddresses() {
        connectivityInfo.ipv4.internalIp = nil
        connectivityInfo.ipv4.connectionAvailable = false
        connectivityInfo.ipv6.internalIp = nil
        connectivityInfo.ipv6.connectionAvailable = false
        let allowedInterfaces = interfaceNames(for: activeNetworkType)

        if let overrides = localIpOverrides?() {
            log("using override addresses ipv4=\(overrides.ipv4 ?? "nil") ipv6=\(overrides.ipv6 ?? "nil")", checkId: activeCheckId)
            if let ipv4 = overrides.ipv4 {
                connectivityInfo.ipv4.internalIp = ipv4
                connectivityInfo.ipv4.connectionAvailable = true
            }

            if let ipv6 = overrides.ipv6,
               !ipv6.uppercased().hasPrefix(ConnectivityService.internalIpV6Prefix) {
                connectivityInfo.ipv6.internalIp = ipv6
                connectivityInfo.ipv6.connectionAvailable = true
            }
        } else if let provider = observedAddressProvider {
            let observed = provider()
            log("using injected interface snapshot for \(observed.keys.count) interfaces", checkId: activeCheckId)
            applyObservedAddresses(observed, allowedInterfaces: allowedInterfaces)
        } else {
            log("collecting local addresses via getifaddrs", checkId: activeCheckId)
            let observed = getLocalIpAddresses()
            applyObservedAddresses(observed, allowedInterfaces: allowedInterfaces)
        }

        log("local snapshot ipv4=\(connectivityInfo.ipv4.internalIp ?? "nil") ipv6=\(connectivityInfo.ipv6.internalIp ?? "nil")", checkId: activeCheckId)
    }

    private func applyObservedAddresses(_ observed: [String: (ipv4: String?, ipv6: String?)], allowedInterfaces: [String]?) {
        let prioritized: [String]
        if let allowed = allowedInterfaces, !allowed.isEmpty {
            prioritized = allowed
        } else {
            let preferredOrder = InterfaceNames.wifi + InterfaceNames.cellular + InterfaceNames.wired
            prioritized = observed.keys.sorted { lhs, rhs in
                let leftIndex = preferredOrder.firstIndex(of: lhs) ?? Int.max
                let rightIndex = preferredOrder.firstIndex(of: rhs) ?? Int.max
                if leftIndex == rightIndex {
                    return lhs < rhs
                }
                return leftIndex < rightIndex
            }
        }

        if let (iface, ip) = prioritized.compactMap({ iface -> (String, String)? in
            guard let ip = observed[iface]?.ipv4 else { return nil }
            return (iface, ip)
        }).first {
            connectivityInfo.ipv4.internalIp = ip
            connectivityInfo.ipv4.connectionAvailable = true
            log("selected ipv4 \(ip) from \(iface) [\(interfaceKind(for: iface))]", checkId: activeCheckId)
        } else {
            connectivityInfo.ipv4.internalIp = nil
            connectivityInfo.ipv4.connectionAvailable = false
            log("no ipv4 found matching interfaces \(allowedInterfaces?.joined(separator: ",") ?? "any")", checkId: activeCheckId)
        }

        if let (iface, ip) = prioritized.compactMap({ iface -> (String, String)? in
            guard let ip = observed[iface]?.ipv6 else { return nil }
            return (iface, ip)
        }).first {
            connectivityInfo.ipv6.internalIp = ip
            connectivityInfo.ipv6.connectionAvailable = true
            log("selected ipv6 \(ip) from \(iface) [\(interfaceKind(for: iface))]", checkId: activeCheckId)
        } else {
            connectivityInfo.ipv6.internalIp = nil
            connectivityInfo.ipv6.connectionAvailable = false
            log("no ipv6 found matching interfaces \(allowedInterfaces?.joined(separator: ",") ?? "any")", checkId: activeCheckId)
        }
    }

    ///
    private func checkIPV4() {
        guard !ipv4Finished else {
            log("ipv4 check skipped: already finished", checkId: activeCheckId)
            return
        }

        guard !ipv4InProgress else {
            log("ipv4 check skipped: already in progress", checkId: activeCheckId)
            return
        }

        ipv4InProgress = true
        let checkId = self.activeCheckId
        self.connectivityInfo.ipv4.connectionAvailable = false
        self.connectivityInfo.ipv4.externalIp = nil
        log("ipv4 fetch started (checkId=\(checkId))", checkId: checkId)

        controlServer.getSettings { [weak self] in
            guard let self = self else { return }
            self.controlServer.getIpv4( success: { [weak self] response in
                guard let self = self, checkId == self.activeCheckId else { return }
                self.connectivityInfo.ipv4.connectionAvailable = true
                self.connectivityInfo.ipv4.externalIp = response.ip
                self.finishIPv4Check(for: checkId)
            }, error: { [weak self] error in
                guard let self = self, checkId == self.activeCheckId else { return }
                self.log("ipv4 fetch failed with error=\(String(describing: error))", checkId: checkId)
                self.connectivityInfo.ipv4.connectionAvailable = false
                self.connectivityInfo.ipv4.externalIp = nil
                self.finishIPv4Check(for: checkId)
            })
        } error: { [weak self] error in
            guard let self = self, checkId == self.activeCheckId else { return }
            self.log("ipv4 settings fetch failed with error=\(String(describing: error))", checkId: checkId)
            self.connectivityInfo.ipv4.connectionAvailable = false
            self.connectivityInfo.ipv4.externalIp = nil
            self.finishIPv4Check(for: checkId)
        }
    }
    
    private func finishIPv4Check(for checkId: Int) {
        guard checkId == activeCheckId else { return }
        self.ipv4Finished = true
        self.ipv4InProgress = false
        log("ipv4 finished internal=\(connectivityInfo.ipv4.internalIp ?? "nil") external=\(connectivityInfo.ipv4.externalIp ?? "nil") available=\(connectivityInfo.ipv4.connectionAvailable)", checkId: checkId)
        self.callCallback(for: checkId)
    }
    
    private func finishIPv6Check(for checkId: Int) {
        guard checkId == activeCheckId else { return }
        self.ipv6Finished = true
        self.ipv6InProgress = false
        log("ipv6 finished internal=\(connectivityInfo.ipv6.internalIp ?? "nil") external=\(connectivityInfo.ipv6.externalIp ?? "nil") available=\(connectivityInfo.ipv6.connectionAvailable)", checkId: checkId)
        self.callCallback(for: checkId)
    }

    ///
    private func checkIPV6() {
        guard !ipv6Finished else {
            log("ipv6 check skipped: already finished", checkId: activeCheckId)
            return
        }

        guard !ipv6InProgress else {
            log("ipv6 check skipped: already in progress", checkId: activeCheckId)
            return
        }

        ipv6InProgress = true
        let checkId = self.activeCheckId
        self.connectivityInfo.ipv6.externalIp = nil
        self.connectivityInfo.ipv6.connectionAvailable = (self.connectivityInfo.ipv6.internalIp != nil)
        log("ipv6 fetch started (initial available=\(self.connectivityInfo.ipv6.connectionAvailable))", checkId: checkId)
        
        controlServer.getIpv6( success: { [weak self] response in
            guard let self = self, checkId == self.activeCheckId else { return }
            if self.connectivityInfo.ipv6.internalIp != nil {
                self.connectivityInfo.ipv6.connectionAvailable = true
                self.connectivityInfo.ipv6.externalIp = response.ip
            } else {
                self.log("ipv6 fetch returned external ip without local address; treating as unavailable", checkId: checkId)
                self.connectivityInfo.ipv6.connectionAvailable = false
                self.connectivityInfo.ipv6.externalIp = nil
            }
            self.finishIPv6Check(for: checkId)
        }, error: { [weak self] error in
            guard let self = self, checkId == self.activeCheckId else { return }
            self.log("ipv6 fetch failed with error=\(String(describing: error))", checkId: checkId)
            self.connectivityInfo.ipv6.connectionAvailable = false
            self.connectivityInfo.ipv6.externalIp = nil
            self.finishIPv6Check(for: checkId)
        })
    }

    ///
    private func callCallback(for checkId: Int) {
        guard checkId == activeCheckId else { return }
        if (ipv4Finished && ipv6Finished) {
            self.ipsWasChecked = true
            self.lastCachedNetworkType = activeNetworkType
            let callback = self.callback
            self.callback = nil
            callback?(connectivityInfo)
            log("delivering connectivity result ipv4_internal=\(connectivityInfo.ipv4.internalIp ?? "nil") ipv4_external=\(connectivityInfo.ipv4.externalIp ?? "nil") ipv6_internal=\(connectivityInfo.ipv6.internalIp ?? "nil") ipv6_external=\(connectivityInfo.ipv6.externalIp ?? "nil")", checkId: checkId)
        }
    }
}

private extension ConnectivityService {
    func log(_ message: String, checkId: Int? = nil) {
        #if DEBUG
        let output = message
        #else
        let output = obfuscateSensitiveData(in: message)
        #endif
        if let checkId = checkId {
            Log.logger.debug("[ConnectivityService][check \(checkId)] \(output)")
        } else {
            Log.logger.debug("[ConnectivityService] \(output)")
        }
    }

    func obfuscateSensitiveData(in message: String) -> String {
        let ipv4Pattern = #"\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\b"#
        let ipv6Pattern = #"\b([0-9A-Fa-f]{1,4})(:[0-9A-Fa-f]{0,4}){1,7}\b"#

        var result = message

        if let ipv4Regex = try? NSRegularExpression(pattern: ipv4Pattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = ipv4Regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1...***")
        }

        if let ipv6Regex = try? NSRegularExpression(pattern: ipv6Pattern, options: []) {
            let nsString = NSMutableString(string: result)
            let range = NSRange(location: 0, length: nsString.length)
            let matches = ipv6Regex.matches(in: result, options: [], range: range)
            for match in matches.reversed() {
                let replacement = "\(nsString.substring(with: match.range(at: 1))):...:****"
                nsString.replaceCharacters(in: match.range, with: replacement)
            }
            result = String(nsString)
        }

        return result
    }

    func networkTypeName(_ type: RMBTNetworkType?) -> String {
        guard let type = type else { return "nil" }
        switch type {
        case .wifi: return "wifi"
        case .cellular: return "cellular"
        case .none: return "none"
        case .browser: return "browser"
        case .unknown: return "unknown"
        }
    }

    func interfaceKind(for name: String) -> String {
        if InterfaceNames.wifi.contains(name) { return "wifi" }
        if InterfaceNames.cellular.contains(name) { return "cellular" }
        if InterfaceNames.wired.contains(name) { return "wired" }
        return "other"
    }

    func interfaceNames(for networkType: RMBTNetworkType?) -> [String]? {
        guard let type = networkType else { return nil }
        switch type {
        case .wifi:
            return InterfaceNames.wifi
        case .cellular:
            return InterfaceNames.cellular
        default:
            return nil
        }
    }

    func ensureSocket() -> GCDAsyncUdpSocket {
        if let socket = udpSocket { return socket }
        let socket = GCDAsyncUdpSocket(delegate: self, delegateQueue: self.socketQueue)
        udpSocket = socket
        return socket
    }
}

// MARK: IP addresses

///
extension ConnectivityService {
    
    // Source: https://stackoverflow.com/a/53528838
    private struct InterfaceNames {
        static let wifi = ["en0"]
        static let wired = ["en2", "en3", "en4"]
        static let cellular = ["pdp_ip0","pdp_ip1","pdp_ip2","pdp_ip3"]
        static let supported = wifi + wired + cellular
    }
    
    static let internalIpV6Prefix = "FE80"
    
    // Source: https://stackoverflow.com/a/53528838
    fileprivate func getLocalIpAddresses() -> [String: (ipv4: String?, ipv6: String?)] {
        let checkId = activeCheckId
        var observed: [String: (ipv4: String?, ipv6: String?)] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var pointer = ifaddr
            while pointer != nil {
                defer { pointer = pointer?.pointee.ifa_next }
                
                guard let interface = pointer?.pointee,
                    interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) || interface.ifa_addr.pointee.sa_family == UInt8(AF_INET6),
                    let interfaceName = interface.ifa_name,
                    let interfaceNameFormatted = String(cString: interfaceName, encoding: .utf8),
                    InterfaceNames.supported.contains(interfaceNameFormatted)
                    else { continue }
                
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                
                getnameinfo(interface.ifa_addr,
                    socklen_t(interface.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    socklen_t(0),
                    NI_NUMERICHOST)
                
                guard let formattedIpAddress = String(cString: hostname, encoding: .utf8),
                    !formattedIpAddress.isEmpty
                    else { continue }
                
                var entry = observed[interfaceNameFormatted] ?? (ipv4: nil, ipv6: nil)

                if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                    if entry.ipv4 != formattedIpAddress {
                        entry.ipv4 = formattedIpAddress
                        log("observed ipv4 \(formattedIpAddress) on \(interfaceNameFormatted) [\(interfaceKind(for: interfaceNameFormatted))]", checkId: checkId)
                    }
                }
                
                if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET6),
                   !formattedIpAddress.uppercased().hasPrefix(ConnectivityService.internalIpV6Prefix) {
                    if entry.ipv6 != formattedIpAddress {
                        entry.ipv6 = formattedIpAddress
                        log("observed global ipv6 \(formattedIpAddress) on \(interfaceNameFormatted) [\(interfaceKind(for: interfaceNameFormatted))]", checkId: checkId)
                    }
                }

                observed[interfaceNameFormatted] = entry
            }
            
            if RMBTSettings.shared.forceIPv4 {
                for key in observed.keys {
                    observed[key]?.ipv6 = nil
                }
            }
            
            freeifaddrs(ifaddr)
        }
        return observed
    }

    ///
    fileprivate func getLocalIpAddressesFromSocket() {
        if let socket = udpSocket, socket.isConnected() {
            self.updateConnectivityInfo(with: socket)
        }
        else {
            let socket = ensureSocket()
            socket.setupSocket()
            
            Log.logger.debug("get local address from socket is prefered IPv4:\(socket.isIPv4Preferred()), prefered IPv6:\(socket.isIPv6Preferred()), enabled IPv4:\(socket.isIPv4Enabled()), enabled IPv6: \(socket.isIPv6Enabled())")
            let host = URL(string: RMBTConfig.shared.RMBT_URL_HOST)?.host ?? "specure.com"

            // connect to any host
            do {
                try socket.connect(toHost: host, onPort: 11111) // TODO: which host, which port? // try!
            } catch {
                let observed = getLocalIpAddresses()
                applyObservedAddresses(observed, allowedInterfaces: interfaceNames(for: activeNetworkType))
                checkIPV4()
                checkIPV6()
            }
        }
    }

    func updateConnectivityInfo(with sock: GCDAsyncUdpSocket) {
        if let ip = sock.localHost_IPv4() {
            connectivityInfo.ipv4.internalIp = ip
        }
        if let ip = sock.localHost_IPv6() {
            connectivityInfo.ipv6.internalIp = ip
            // TODO: Check external ip
//            connectivityInfo.ipv6.externalIp = ip
        }
        
        Log.logger.debug("local ipv4 address from socket: \(String(describing: self.connectivityInfo.ipv4.internalIp))")
        Log.logger.debug("local ipv6 address from socket: \(String(describing: self.connectivityInfo.ipv6.internalIp))")
    }
}

// MARK: GCDAsyncUdpSocketDelegate

///
extension ConnectivityService: GCDAsyncUdpSocketDelegate {

    public func udpSocket(_ sock: GCDAsyncUdpSocket, didNotConnect error: Error?) {
        Log.logger.debug("didNotConnect: \(String(describing: error))")
        let observed = getLocalIpAddresses()
        applyObservedAddresses(observed, allowedInterfaces: interfaceNames(for: activeNetworkType))
        checkIPV4()
        checkIPV6()
    }
    
    public func udpSocketDidClose(_ sock: GCDAsyncUdpSocket, withError error: Error?) {
        Log.logger.debug("udpSocketDidClose: \(String(describing: error))")
        let observed = getLocalIpAddresses()
        applyObservedAddresses(observed, allowedInterfaces: interfaceNames(for: activeNetworkType))
        checkIPV4()
        checkIPV6()
    }
    
    public func udpSocket(_ sock: GCDAsyncUdpSocket, didConnectToAddress address: Data) {
        self.updateConnectivityInfo(with: sock)
        sock.close()
        checkIPV4()
        checkIPV6()
    }
}
