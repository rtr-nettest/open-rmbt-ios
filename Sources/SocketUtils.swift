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

/// contains convenience methods for working with sockets
extension GCDAsyncSocket {
    ///
    func writeLine(line: String, withTimeout timeout: TimeInterval, tag: Int) { // TODO: use nano seconds timeouts
        var line = line
        
        // append \n to command if not already done
        if !line.hasSuffix("\n") {
            line = line + "\n"
        }
        
        Log.logger.verbose("-- writing line '\(line)'")
        
        if let lineData = line.data(using: String.Encoding.utf8) {
            self.write(lineData, withTimeout: timeout, tag: tag)
        } else {
            // TODO: return false or error?
        }
    }
    
    ///
    func readLine(tag: Int, withTimeout timeout: TimeInterval) {
        if let data = "\n".data(using: String.Encoding(rawValue: QOS_SOCKET_DEFAULT_CHARACTER_ENCODING)) {
            self.readData(to: data, withTimeout: timeout, tag: tag)
        }
    }
}

extension GCDAsyncSocket {
    func setupSocket() {
        // The IPv4-only / IPv6-only restriction is NOT applied at the socket level. It is applied by
        // sending the measurement request (/testRequest, /coverageRequest) to the version-specific
        // control host, and the server then runs the measurement over that IP version. Sockets stay
        // dual-stack so nothing else (control, connectivity status) is affected.
        self.isIPv4Enabled = true
        self.isIPv6Enabled = true
        self.isIPv4PreferredOverIPv6 = false
    }
}

extension GCDAsyncUdpSocket {
    func setupSocket() {
        // See GCDAsyncSocket.setupSocket() above: the IP-version restriction is applied via the
        // measurement request host, not at the socket level.
        self.setIPv6Enabled(true)
        self.setPreferIPv6()
    }
}

class SocketUtils {

    /// parses NSData object to String using default encoding
    class func parseResponseToString(_ data: Data) -> String? {
        if let str = NSString(data: data, encoding: QOS_SOCKET_DEFAULT_CHARACTER_ENCODING) {
            return str as String
        }

        return nil
    }

}
