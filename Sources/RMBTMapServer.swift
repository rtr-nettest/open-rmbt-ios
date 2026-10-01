/*****************************************************************************************************
 * Copyright 2016 SPECURE GmbH
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
import CoreLocation
import Alamofire
import AlamofireObjectMapper
import ObjectMapper

///
@objc final public class RMBTMapServer: NSObject {

    ///
    @objc public static let shared = RMBTMapServer()

    ///
    private let alamofireManager: Alamofire.Session

    ///
    private let settings = RMBTSettings.shared

    ///
    private var baseUrl: String? {
        // don't store in variable, could be changed in settings
        // Developer override: swap the map server host (keeping the resolved scheme/path), when enabled with a
        // valid hostname. The hostname is validated before it is stored (see RMBTSettingsViewController), so here
        // we only need the enabled flag + a non-empty value.
        if settings.debugUnlocked,
           settings.debugMapServerCustomizationEnabled,
           let host = settings.debugMapServerHostname, !host.isEmpty {
            if let resolved = RMBTControlServer.shared.mapServerURL,
               var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) {
                components.scheme = "https"
                components.host = host
                components.port = nil
                if let overridden = components.url?.absoluteString {
                    return overridden
                }
            }
            // No resolved map URL yet (settings not fetched): fall back to the standard map server path.
            return "https://\(host)/RMBTMapServer"
        }
        return RMBTControlServer.shared.mapServerURL?.absoluteString
    }

    /// The map server base URL currently in effect (honouring the developer override). Exposed so the map screen
    /// can detect when the server changed between appearances and reload its options/tiles.
    var currentBaseURL: String? { baseUrl }

    ///
    private override init() {
        alamofireManager = ServerHelper.configureAlamofireManager()
    }

    ///
    deinit {
        alamofireManager.session.invalidateAndCancel()
    }

// MARK: MapServer
    
    ///
    @objc public func getMapOptions(success successCallback: @escaping (_ response: MapOptionResponse) -> (), error failure: @escaping ErrorCallback) {
        let request = BasicRequest()
        BasicRequestBuilder.addBasicRequestValues(request)
        self.request(HTTPMethod.post, path: "/v2/tiles/info", requestObject: request, success: { (response: MapOptionResponse) in
            successCallback(response)
        } , error: failure)
    }

    ///
    @objc public func getMeasurementsAtCoordinate(_ coordinate: CLLocationCoordinate2D, zoom: Int, params: [String: Any], success successCallback: @escaping (_ response: [SpeedMeasurementResultResponse]) -> (), error failure: @escaping ErrorCallback) {

        Log.logger.debug("Input params: \(params)")

        let mapMeasurementRequest = MapMeasurementRequest()
        mapMeasurementRequest.coords = MapMeasurementRequest.CoordObject()
        mapMeasurementRequest.coords?.latitude = coordinate.latitude
        mapMeasurementRequest.coords?.longitude = coordinate.longitude
        mapMeasurementRequest.coords?.zoom = zoom

        mapMeasurementRequest.options = MapMeasurementRequest.MapOptions()
        mapMeasurementRequest.options?.mapOptions = params["map_options"] as? String

        mapMeasurementRequest.filter = MapMeasurementRequest.Filter()
        mapMeasurementRequest.filter?.period = (params["period"] as? Int)?.description

        if let technology = params["technology"] as? String, !technology.isEmpty, technology != "some" {
            mapMeasurementRequest.filter?.technology = technology
        }

        if let provider = normalizedFilterString(params["provider"]) {
            Log.logger.debug("Using PROVIDER filter: '\(provider)' (operator in params was: '\(params["operator"] ?? "missing")')")
            mapMeasurementRequest.filter?.provider = provider
        } else if let mobileOperator = normalizedFilterString(params["operator"]) {
            Log.logger.debug("Using OPERATOR filter: '\(mobileOperator)'")
            mapMeasurementRequest.filter?.mobileOperator = mobileOperator
        } else {
            Log.logger.debug("No provider/operator filter applied (provider='\(params["provider"] ?? "missing")', operator='\(params["operator"] ?? "missing")')")
        }

        Log.logger.debug("Sending request: map_options=\(mapMeasurementRequest.options?.mapOptions ?? "nil"), period=\(mapMeasurementRequest.filter?.period ?? "nil"), technology=\(mapMeasurementRequest.filter?.technology ?? "nil"), provider=\(mapMeasurementRequest.filter?.provider ?? "nil"), operator=\(mapMeasurementRequest.filter?.mobileOperator ?? "nil")")

        // TODO: Check request and response
        request(.post, path: "/tiles/markers", requestObject: mapMeasurementRequest, success: { (response: MapMeasurementResponse) in
            if let measurements = response.measurements {
                Log.logger.debug("Got \(measurements.count) measurements")
                successCallback(measurements)
            } else {
                failure(NSError(domain: "no measurements", code: -12543, userInfo: nil))
            }
        }, error: failure)
    }

    public func getTileUrlTemplate(_ overlayType: String, params: [String: Any]?) -> String? {
        guard let base = baseUrl else { return nil }
        // baseUrl and layer
        var urlString = base + "/tiles/\(overlayType)?path={z}/{x}/{y}"
        
        // add params
        if let p = params, p.count > 0 {
            let paramString = Self.queryString(from: p)
            if !paramString.isEmpty {
                urlString += "&" + paramString
            }
        }

        Log.logger.debug("Generated tile url: \(urlString)")

        print(urlString)

        return urlString
    }

    /// Builds a `key=value&…` query string from map filter params. Values that are not strings or numbers
    /// (notably `NSNull`, emitted for "all" filters like technology/operator) are skipped — previously these were
    /// force-cast to String and crashed (`Could not cast value of type 'NSNull' to 'NSString'`).
    static func queryString(from params: [String: Any]) -> String {
        params.compactMap { (key, value) -> String? in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let escapedValue: String
            if let stringValue = value as? String {
                escapedValue = stringValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stringValue
            } else if let numberValue = value as? NSNumber {
                escapedValue = String(describing: numberValue)
            } else {
                return nil // skip NSNull / unsupported values (e.g. an "all" filter → no constraint)
            }
            return "\(escapedKey)=\(escapedValue)"
        }
        .joined(separator: "&")
    }
    
    @objc public func getTileUrlForMapOverlayType(_ overlayType: String, x: UInt, y: UInt, zoom: UInt, params: [String: Any]?) -> URL? {
        if let base = baseUrl {
            // baseUrl and layer
            var urlString = base + "/tiles/\(overlayType)?path=\(zoom)/\(x)/\(y)"

            // add params
            if let p = params, p.count > 0 {
                let paramString = Self.queryString(from: p)
                if !paramString.isEmpty {
                    urlString += "&" + paramString
                }
            }

            Log.logger.debug("Generated tile url: \(urlString)")

            print(urlString)
            
            return URL(string: urlString)
        }

        return nil
    }

    @objc(getURLStringForOpenTestUUID:success:) public func getOpenTestUrl(_ openTestUuid: String, success successCallback: @escaping (_ response: String?) -> ()) {
        if let url = RMBTControlServer.shared.openTestBaseURL {
            let theURL = url + openTestUuid
            successCallback(theURL)
        } else {
            RMBTControlServer.shared.getSettings {
                if let url = RMBTControlServer.shared.openTestBaseURL {
                    let theURL = url + openTestUuid
                    successCallback(theURL)
                }
            } error: { error in
                Log.logger.error(error)
                successCallback(nil)
            }
        }
    }

    /// Converts a map filter param value to a non-empty String.
    /// The `/v2/tiles/info` API returns filter values as String (empty for "All")
    /// or numeric IDs (Int/Float) for specific selections. This normalizes both
    /// to a String suitable for the `/tiles/markers` request body.
    private func normalizedFilterString(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.isEmpty ? nil : string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func request<T: BasicResponse>(_ method: Alamofire.HTTPMethod, path: String, requestObject: BasicRequest?, success: @escaping (_ response: T) -> (), error failure: @escaping ErrorCallback) {
        ServerHelper.request(alamofireManager, baseUrl: baseUrl, method: method, path: path, requestObject: requestObject, success: success, error: failure)
    }
}
