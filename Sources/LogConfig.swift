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
    
    /// Kept so the log can be flushed before the app is suspended or terminated — writes happen on a background
    /// queue (see below), so without this the tail of a field log can be lost exactly when it matters most.
    private static weak var fileDestination: FileDestination?

    fileprivate class func setupDestination() {
        let logFilePath = getCurrentLogFilePath()

        let destination = FileDestination(owner: Log.logger, writeToFile: logFilePath, shouldAppend: true)
        // Writes are synchronous on the calling thread by default. The coverage ping loop logs from its own
        // measurement path at up to 10 Hz, so keep file I/O off it.
        destination.logQueue = XCGLogger.logQueue
        Log.logger.add(destination: destination)
        fileDestination = destination

        self.addUDPLogging()
    }

    /// Writes any log lines still queued. Call before the app can be suspended or torn down.
    class func flushLog() {
        fileDestination?.flush()
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

    /// A fixed, locale-independent format on purpose: `DateFormatter.dateStyle = .short` renders `8/4/26` in many
    /// locales, and the slashes turned the file name into a path whose directories do not exist — the destination
    /// then silently failed to open and nothing was ever written to file.
    class func getCurrentLogFileName() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let name = dateFormatter.string(from: Date())
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "rmbt"
        return "\(bundleIdentifier)_\(name)_log.log"
    }

    ///
    class func getLogFolderPath() -> String {
        let cacheDirectory = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        let logDirectory = cacheDirectory + "/logs"

        // try to create logs directory if it doesn't exist yet
        if !FileManager.default.fileExists(atPath: logDirectory) {
            do {
                try FileManager.default.createDirectory(atPath: logDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                // Nothing can be logged about this yet — the destination that would carry it does not exist.
                NSLog("LogConfig: could not create log directory at \(logDirectory): \(error)")
            }
        }

        return logDirectory
    }
}
