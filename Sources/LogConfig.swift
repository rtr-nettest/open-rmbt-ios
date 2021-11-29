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
import XCGLogger

///
class LogConfig {
    
    private static let udpIdentifier = "logging.destination"
    
    /// setup logging system
    class func initLoggingFramework() {
        Log.logger.add(destination: ConsoleDestination(identifier: "RMBTClient.log"))
        #if RELEASE
            // Release config
            Log.logger.setup(.Info, showLogLevel: true, showFileNames: false, showLineNumbers: true, writeToFile: nil) /* .Error */
        #elseif DEBUG || TEST
            // Debug config
            Log.logger.setup(level: .verbose, showLevel: true, showFileNames: false, showLineNumbers: true, writeToFile: nil) // don't need log to file
        #elseif BETA
            // Beta config
            Log.logger.setup(.Debug, showLogLevel: true, showFileNames: false, showLineNumbers: true, writeToFile: nil)
        #else
            // Debug config
            Log.logger.setup(level: .verbose, showLevel: true, showFileNames: false, showLineNumbers: true, writeToFile: nil) // don't need log to file
        #endif
        self.setupDestination()
    }
    
    fileprivate class func setupDestination() {
        let logFilePath = getCurrentLogFilePath()
        
        let destination = FileDestination(owner: Log.logger, writeToFile: logFilePath, shouldAppend: true)
        Log.logger.add(destination: destination)

        self.addUDPLogging()
    }

    @objc static var enableLogging: Bool = false {
        didSet {
            Log.logger.remove(destinationWithIdentifier: LogConfig.udpIdentifier)
            if enableLogging {
                LogConfig.addUDPLogging()
            }
        }
    }
    
    private class func addUDPLogging() {
        guard RMBTSettings.shared.debugLoggingEnabled else { return }
        
        let port = RMBTSettings.shared.debugLoggingPort
        if let host = RMBTSettings.shared.debugLoggingHostname {
            let udpDestination = UDPDestination(owner: Log.logger, identifier: LogConfig.udpIdentifier, host: host, port: port)
            Log.logger.add(destination: udpDestination)
        }
    }
    ///
    class func getCurrentLogFilePath() -> String {
        return getLogFolderPath() + "/" + getCurrentLogFileName()
    }

    ///
    class func getCurrentLogFileName() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        let name = dateFormatter.string(from: Date())
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "rmbt"
        return bundleIdentifier + "_" + name + "_" + "_log.log"
    }

    ///
    class func getLogFolderPath() -> String {
        let cacheDirectory = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        let logDirectory = cacheDirectory + "/logs"

        // try to create logs directory if it doesn't exist yet
        if !FileManager.default.fileExists(atPath: logDirectory) {
            do {
                try FileManager.default.createDirectory(atPath: logDirectory, withIntermediateDirectories: false, attributes: nil)
            } catch {
                // TODO
            }
        }

        return logDirectory
    }
}
