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
    fileprivate lazy var udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: self.socketQueue)
    
    ///
    var callback: ConnectivityInfoCallback?

    ///
    var connectivityInfo = ConnectivityInfo()

    ///
    var ipv4Finished = true

    ///
    var ipv6Finished = true
    
    var ipsWasChecked = false

    deinit {
        self.udpSocket.close()
        self.udpSocket.setDelegate(nil)
        self.callback = nil
    }
    ///
    open func checkConnectivity(_ callback: @escaping ConnectivityInfoCallback) {
        self.callback = callback
        if ipsWasChecked {
            self.callback?(connectivityInfo)
        }
        
        getLocalIpAddresses()

        checkIPV4()
        checkIPV6()
    }

    ///
    private func checkIPV4() {
        if self.ipv4Finished == true {
            self.ipv4Finished = false
            
            RMBTControlServer.shared.getSettings {
                RMBTControlServer.shared.getIpv4( success: { [weak self] response in
                    self?.connectivityInfo.ipv4.connectionAvailable = true
                    self?.connectivityInfo.ipv4.externalIp = response.ip
                    self?.finishIPv4Check()
                }, error: { [weak self] error in
                    self?.connectivityInfo.ipv4.connectionAvailable = false
                    self?.finishIPv4Check()
                })
            } error: { [weak self] error in
                self?.connectivityInfo.ipv4.connectionAvailable = false
                self?.finishIPv4Check()
            }

            
        }
    }
    
    private func finishIPv4Check() {
        self.ipv4Finished = true
        self.callCallback()
    }
    
    private func finishIPv6Check() {
        self.ipv6Finished = true
        self.callCallback()
    }

    ///
    private func checkIPV6() {
        
        self.connectivityInfo.ipv6.connectionAvailable = (self.connectivityInfo.ipv6.internalIp != nil)
        
        RMBTControlServer.shared.getIpv6( success: { [weak self] response in
            self?.connectivityInfo.ipv6.connectionAvailable = true
            self?.connectivityInfo.ipv6.externalIp = response.ip
            self?.finishIPv6Check()
        }, error: { [weak self] error in
            self?.connectivityInfo.ipv6.connectionAvailable = false
            self?.finishIPv6Check()
        })
    }

    ///
    private func callCallback() {
        if (ipv4Finished && ipv6Finished) {
            self.ipsWasChecked = true
            self.callback?(connectivityInfo)
        }
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
    fileprivate func getLocalIpAddresses() {
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
                
                if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                    if self.connectivityInfo.ipv4.internalIp != formattedIpAddress {
                        self.connectivityInfo.ipv4.internalIp = formattedIpAddress
                        Log.logger.debug("local ipv4 address from getifaddrs: \(formattedIpAddress)")
                    }
                }
                
                if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET6),
                   !formattedIpAddress.uppercased().hasPrefix(ConnectivityService.internalIpV6Prefix) {
                    if self.connectivityInfo.ipv6.internalIp != formattedIpAddress {
                        self.connectivityInfo.ipv6.internalIp = formattedIpAddress
                        Log.logger.debug("local ipv6 address from getifaddrs: \(formattedIpAddress)")
                    }
                }
            }
            
            if RMBTSettings.shared.forceIPv4 {
                self.connectivityInfo.ipv6.internalIp = nil
                self.connectivityInfo.ipv6.externalIp = nil
                self.connectivityInfo.ipv6.connectionAvailable = false
            }
            
            freeifaddrs(ifaddr)
        }
    }

    ///
    fileprivate func getLocalIpAddressesFromSocket() {
        if self.udpSocket.isConnected() {
            self.updateConnectivityInfo(with: self.udpSocket)
        }
        else {
            udpSocket.setupSocket()
            
            Log.logger.debug("get local address from socket is prefered IPv4:\(udpSocket.isIPv4Preferred()), prefered IPv6:\(udpSocket.isIPv6Preferred()), enabled IPv4:\(udpSocket.isIPv4Enabled()), enabled IPv6: \(udpSocket.isIPv6Enabled())")
            let host = URL(string: RMBTConfig.shared.RMBT_URL_HOST)?.host ?? "specure.com"

            // connect to any host
            do {
                try udpSocket.connect(toHost: host, onPort: 11111) // TODO: which host, which port? // try!
            } catch {
                getLocalIpAddresses() // fallback
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
        getLocalIpAddresses() // fallback
        checkIPV4()
        checkIPV6()
    }
    
    public func udpSocketDidClose(_ sock: GCDAsyncUdpSocket, withError error: Error?) {
        Log.logger.debug("udpSocketDidClose: \(String(describing: error))")
        getLocalIpAddresses() // fallback
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
