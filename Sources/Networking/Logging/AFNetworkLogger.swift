import Foundation
import Alamofire

/// Central network logger that renders the raw request and response payloads once per transaction.
/// The logger is intentionally lightweight: it focuses on the essentials (method, URL, headers, body preview, metrics)
/// while keeping formatting human friendly and machine parsable.
final class AFNetworkLogger: EventMonitor {
    let queue = DispatchQueue(label: "at.rtr.rmbt.network.logger")

    private let redactedHeaderNames: Set<String> = ["authorization", "cookie", "x-api-key"]
    private let redactedJsonKeys: Set<String> = ["token", "authorization", "password"]
    private let bodyPreviewLimit = 64 * 1024 // 64 KB guard against very large payloads

    private var metricsStore: [ObjectIdentifier: URLSessionTaskMetrics] = [:]

    // MARK: - EventMonitor

    func request(_ request: Request, didCreateInitialURLRequest urlRequest: URLRequest) {
        guard shouldLog else { return }

        Log.logger.debug(renderRequest(id: identifier(for: request), urlRequest: urlRequest))
    }

    func request(_ request: Request, didGatherTaskMetrics metrics: URLSessionTaskMetrics) {
        guard shouldLog else { return }

        metricsStore[ObjectIdentifier(request)] = metrics
    }

    func request(_ request: Request, didCompleteTask task: URLSessionTask, with error: AFError?) {
        guard shouldLog else { return }

        let requestID = identifier(for: request)
        let httpResponse = task.response as? HTTPURLResponse
        let metrics = metricsStore.removeValue(forKey: ObjectIdentifier(request))
        let responseData = (request as? DataRequest)?.data

        Log.logger.debug(
            renderResponse(
                id: requestID,
                originalRequest: request.request,
                response: httpResponse,
                data: responseData,
                error: error,
                metrics: metrics
            )
        )
    }
}

// MARK: - Rendering helpers

private extension AFNetworkLogger {
    var shouldLog: Bool {
        #if DEBUG
        return true
        #else
        return RMBTSettings.shared.debugLoggingEnabled
        #endif
    }

    func identifier(for request: Request) -> String {
        let raw = ObjectIdentifier(request).hashValue & 0xffff
        return String(format: "%04X", raw)
    }

    func renderRequest(id: String, urlRequest: URLRequest) -> String {
        var components: [String] = []
        let method = urlRequest.httpMethod ?? "UNKNOWN"
        let url = urlRequest.url?.absoluteString ?? "<nil>"
        components.append("#\(id) REQUEST \(method) \(url)")

        let headers = sanitizeHeaders(urlRequest.allHTTPHeaderFields ?? [:])
        components.append(headersDescription(headers))

        components.append("Timeout: \(String(format: "%.1f", urlRequest.timeoutInterval))s  Cache: \(urlRequest.cachePolicy)")

        if let bodyLine = bodyDescription(
            data: extractBodyData(from: urlRequest),
            contentType: headers["Content-Type"]
        ) {
            components.append(bodyLine)
        } else {
            components.append("Body: ∅")
        }

        components.append("-- END REQUEST #\(id) --")
        return components.joined(separator: "\n")
    }

    func renderResponse(
        id: String,
        originalRequest: URLRequest?,
        response: HTTPURLResponse?,
        data: Data?,
        error: Error?,
        metrics: URLSessionTaskMetrics?
    ) -> String {
        var components: [String] = []

        let statusLine: String
        if let response = response {
            let method = originalRequest?.httpMethod ?? response.url?.scheme?.uppercased() ?? "REQUEST"
            let url = response.url?.absoluteString ?? originalRequest?.url?.absoluteString ?? "<nil>"
            statusLine = "#\(id) RESPONSE \(response.statusCode) for \(method) \(url)"
        } else {
            let method = originalRequest?.httpMethod ?? "REQUEST"
            let url = originalRequest?.url?.absoluteString ?? "<nil>"
            statusLine = "#\(id) RESPONSE (no HTTPURLResponse) for \(method) \(url)"
        }
        components.append(statusLine)

        if let metrics = metrics {
            components.append(metricsDescription(metrics))
        }

        if let response = response {
            let headers = sanitizeHeaders(response.allHeaderFields)
            components.append(headersDescription(headers))
        } else {
            components.append("Headers: ∅")
        }

        if let description = bodyDescription(
            data: data,
            contentType: response?.value(forHTTPHeaderField: "Content-Type")
        ) {
            components.append(description)
        } else {
            components.append("Body: ∅")
        }

        if let error = error {
            components.append("Error: \(error.localizedDescription)")
        }

        components.append("-- END RESPONSE #\(id) --")
        return components.joined(separator: "\n")
    }

    func sanitizeHeaders(_ headers: [AnyHashable: Any]) -> [String: String] {
        var sanitized: [String: String] = [:]

        headers.forEach { key, value in
            let headerName: String
            if let stringKey = key as? String {
                headerName = stringKey
            } else {
                headerName = "\(key)".trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let lowered = headerName.lowercased()
            let shouldRedact = redactedHeaderNames.contains(lowered)
            let valueString = String(describing: value)
            sanitized[headerName] = shouldRedact && !valueString.isEmpty ? "<redacted>" : valueString
        }

        return sanitized
    }

    func headersDescription(_ headers: [String: String]) -> String {
        guard !headers.isEmpty else { return "Headers: ∅" }
        let sorted = headers.sorted { $0.key.lowercased() < $1.key.lowercased() }
        let formatted = sorted.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ", ")
        return "Headers: {\(formatted)}"
    }

    func bodyDescription(data: Data?, contentType: String?) -> String? {
        guard let data = data, !data.isEmpty else { return nil }

        let (bodyString, encoding, truncated) = decodeBody(data)
        let truncationSuffix = truncated ? ", truncated" : ""
        let bodyType = bodyContentTypeHint(contentType: contentType, bodyString: bodyString, encoding: encoding)

        if let bodyString = bodyString {
            if encoding == "base64" {
                return "Body (\(bodyType), \(data.count) B\(truncationSuffix), base64 preview):\n\(bodyString)"
            }
            let sanitized = bodyType == "json" ? redactJsonString(bodyString) : bodyString
            return "Body (\(bodyType), \(data.count) B\(truncationSuffix)):\n\(sanitized)"
        }

        if let encoding = encoding {
            return "Body (\(bodyType), \(data.count) B\(truncationSuffix), encoded as \(encoding))"
        }

        return "Body (\(bodyType), \(data.count) B\(truncationSuffix), binary preview unavailable)"
    }

    func decodeBody(_ data: Data) -> (String?, String?, Bool) {
        let truncated = data.count > bodyPreviewLimit
        let previewData = truncated ? data.prefix(bodyPreviewLimit) : data

        if let string = String(data: previewData, encoding: .utf8) {
            return (string, "utf8", truncated)
        }

        if let string = String(data: previewData, encoding: .ascii) {
            return (string, "ascii", truncated)
        }

        let base64 = previewData.base64EncodedString()
        return (base64, "base64", truncated)
    }

    func bodyContentTypeHint(contentType: String?, bodyString: String?, encoding: String?) -> String {
        if let contentType = contentType?.lowercased() {
            if contentType.contains("json") { return "json" }
            if contentType.contains("xml") { return "xml" }
            if contentType.contains("text") { return "text" }
        }
        if encoding == "base64" {
            return "binary"
        }
        if bodyString != nil { return "text" }
        return "binary"
    }

    func redactJsonString(_ json: String) -> String {
        var redacted = json
        for key in redactedJsonKeys {
            let escapedKey = NSRegularExpression.escapedPattern(for: key)
            let pattern = "(?i)(\"\(escapedKey)\"\\s*:\\s*\")([^\"\\\\]*)(\")"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(redacted.startIndex..<redacted.endIndex, in: redacted)
            redacted = regex.stringByReplacingMatches(in: redacted, options: [], range: range, withTemplate: "$1<redacted>$3")
        }
        return redacted
    }

    func metricsDescription(_ metrics: URLSessionTaskMetrics) -> String {
        let totalMs = metrics.taskInterval.duration * 1000
        var parts: [String] = ["Duration: \(totalMs.roundedString()) ms"]

        if let transaction = metrics.transactionMetrics.last {
            if let dns = intervalMs(start: transaction.domainLookupStartDate, end: transaction.domainLookupEndDate) {
                parts.append("dns=\(dns) ms")
            }
            if let connect = intervalMs(start: transaction.connectStartDate, end: transaction.connectEndDate) {
                parts.append("connect=\(connect) ms")
            }
            if let tls = intervalMs(start: transaction.secureConnectionStartDate, end: transaction.secureConnectionEndDate) {
                parts.append("tls=\(tls) ms")
            }
            if let firstByte = intervalMs(start: transaction.requestStartDate, end: transaction.responseStartDate) {
                parts.append("ttfb=\(firstByte) ms")
            }
        }

        return "Metrics: " + parts.joined(separator: "  ")
    }

    func intervalMs(start: Date?, end: Date?) -> String? {
        guard let start = start, let end = end else { return nil }
        let value = end.timeIntervalSince(start) * 1000
        return value.roundedString()
    }

    func extractBodyData(from urlRequest: URLRequest) -> Data? {
        if let data = urlRequest.httpBody {
            return data
        }

        guard let stream = urlRequest.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var data = Data()
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
            if data.count >= bodyPreviewLimit {
                break
            }
        }
        return data
    }
}

private extension Double {
    func roundedString() -> String {
        String(format: "%.1f", self)
    }
}
