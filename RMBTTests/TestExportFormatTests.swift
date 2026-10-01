import Testing
import Foundation
@testable import RMBT

@Suite("TestExportFormat")
struct TestExportFormatTests {

    @Suite("urlPath")
    struct URLPath {
        @Test("WHEN requesting the PDF export path THEN it is the unlocalized $lang template")
        func pdfPathIsUnlocalizedTemplate() {
            #expect(TestExportFormat.pdf.urlPath == "/export/pdf/$lang")
        }

        @Test("WHEN requesting the xlsx or csv export path THEN it is the shared opentests search path")
        func xlsxAndCSVPathsAreUnlocalized() {
            #expect(TestExportFormat.xlsx.urlPath == "/opentests/search")
            #expect(TestExportFormat.csv.urlPath == "/opentests/search")
        }
    }

    @Suite("downloadRequest(baseURL:openTestUUIDs:maxResults:)")
    struct DownloadRequest {
        private let baseURL = URL(string: "https://netztest.example.com")!

        @Test("WHEN building the PDF export request THEN $lang resolves to a supported locale (de or en)")
        func pdfRequestLocalizesLanguage() {
            let request = TestExportFormat.pdf.downloadRequest(baseURL: baseURL, openTestUUIDs: ["uuid-1"])
            let path = request.url?.path

            #expect(["/export/pdf/de", "/export/pdf/en"].contains(path))
        }

        @Test("WHEN building the xlsx or csv export request THEN the path stays the shared opentests search path")
        func xlsxAndCSVRequestPathsAreUnlocalized() {
            let xlsxRequest = TestExportFormat.xlsx.downloadRequest(baseURL: baseURL, openTestUUIDs: ["uuid-1"])
            let csvRequest = TestExportFormat.csv.downloadRequest(baseURL: baseURL, openTestUUIDs: ["uuid-1"])

            #expect(xlsxRequest.url?.path == "/opentests/search")
            #expect(csvRequest.url?.path == "/opentests/search")
        }
    }
}
