import Testing
import Foundation
@testable import ScipioManager

@Suite("GCS Bucket Service Tests")
struct GCSBucketServiceTests {

    // MARK: - XML Parser Tests

    @Test("Parses valid S3 ListObjectsV2 XML response")
    func parseValidXML() {
        let xml = """
        <?xml version='1.0' encoding='UTF-8'?>
        <ListBucketResult xmlns='http://doc.s3.amazonaws.com/2006-03-01'>
            <Name>test-bucket</Name>
            <Prefix>XCFrameworks/</Prefix>
            <KeyCount>2</KeyCount>
            <MaxKeys>1000</MaxKeys>
            <IsTruncated>false</IsTruncated>
            <Contents>
                <Key>XCFrameworks/Alamofire/abc123.zip</Key>
                <Size>1048576</Size>
                <LastModified>2026-02-10T12:00:00.000Z</LastModified>
                <ETag>"d41d8cd98f00b204e9800998ecf8427e"</ETag>
            </Contents>
            <Contents>
                <Key>XCFrameworks/RxSwift/def456.zip</Key>
                <Size>2097152</Size>
                <LastModified>2026-02-11T15:30:00.000Z</LastModified>
                <ETag>"9a0364b9e99bb480dd25e1f0284c8555"</ETag>
            </Contents>
        </ListBucketResult>
        """

        let parser = S3ListResponseParser(data: xml.data(using: .utf8)!)
        #expect(parser.entries.count == 2)

        let first = parser.entries[0]
        #expect(first.key == "XCFrameworks/Alamofire/abc123.zip")
        #expect(first.size == 1_048_576)
        #expect(first.frameworkName == "Alamofire")  // second-to-last component
        #expect(first.cacheHash == "abc123")

        let second = parser.entries[1]
        #expect(second.key == "XCFrameworks/RxSwift/def456.zip")
        #expect(second.size == 2_097_152)
        #expect(second.frameworkName == "RxSwift")  // second-to-last component
    }

    @Test("Parses continuation token")
    func parseContinuationToken() {
        let xml = """
        <?xml version='1.0' encoding='UTF-8'?>
        <ListBucketResult xmlns='http://doc.s3.amazonaws.com/2006-03-01'>
            <Name>test-bucket</Name>
            <KeyCount>1</KeyCount>
            <MaxKeys>1</MaxKeys>
            <IsTruncated>true</IsTruncated>
            <NextContinuationToken>abc123token</NextContinuationToken>
            <Contents>
                <Key>XCFrameworks/Test/file.zip</Key>
                <Size>100</Size>
                <LastModified>2026-01-01T00:00:00.000Z</LastModified>
                <ETag>"etag"</ETag>
            </Contents>
        </ListBucketResult>
        """

        let parser = S3ListResponseParser(data: xml.data(using: .utf8)!)
        #expect(parser.entries.count == 1)
        #expect(parser.nextContinuationToken == "abc123token")
    }

    @Test("Parses empty result")
    func parseEmptyResult() {
        let xml = """
        <?xml version='1.0' encoding='UTF-8'?>
        <ListBucketResult xmlns='http://doc.s3.amazonaws.com/2006-03-01'>
            <Name>test-bucket</Name>
            <KeyCount>0</KeyCount>
            <MaxKeys>1000</MaxKeys>
            <IsTruncated>false</IsTruncated>
        </ListBucketResult>
        """

        let parser = S3ListResponseParser(data: xml.data(using: .utf8)!)
        #expect(parser.entries.isEmpty)
        #expect(parser.nextContinuationToken == nil)
    }

    @Test("Parses entries with missing optional fields gracefully")
    func parseMissingFields() {
        let xml = """
        <?xml version='1.0' encoding='UTF-8'?>
        <ListBucketResult>
            <Contents>
                <Key>test/file.zip</Key>
            </Contents>
        </ListBucketResult>
        """

        let parser = S3ListResponseParser(data: xml.data(using: .utf8)!)
        #expect(parser.entries.count == 1)
        #expect(parser.entries[0].key == "test/file.zip")
        #expect(parser.entries[0].size == 0)
        #expect(parser.entries[0].etag == "")
    }

    @Test("ETag quotes stripped")
    func etagQuotesStripped() {
        let xml = """
        <?xml version='1.0' encoding='UTF-8'?>
        <ListBucketResult>
            <Contents>
                <Key>k</Key>
                <Size>10</Size>
                <LastModified>2026-01-01T00:00:00.000Z</LastModified>
                <ETag>"abc123"</ETag>
            </Contents>
        </ListBucketResult>
        """

        let parser = S3ListResponseParser(data: xml.data(using: .utf8)!)
        #expect(parser.entries[0].etag == "abc123")
    }

    @Test("Parses large entry count")
    func parseLargeCount() {
        var xml = "<?xml version='1.0' encoding='UTF-8'?><ListBucketResult>"
        for i in 0..<100 {
            xml += """
            <Contents>
                <Key>XCFrameworks/FW\(i)/hash.zip</Key>
                <Size>\(i * 1000)</Size>
                <LastModified>2026-02-01T00:00:00.000Z</LastModified>
                <ETag>"etag\(i)"</ETag>
            </Contents>
            """
        }
        xml += "</ListBucketResult>"

        let parser = S3ListResponseParser(data: xml.data(using: .utf8)!)
        #expect(parser.entries.count == 100)
    }

    // MARK: - BucketStats

    @Test("BucketStats totalSizeFormatted returns readable string")
    func bucketStatsFormatted() {
        let stats = BucketStats(totalEntries: 10, totalSize: 50_000_000, frameworkCount: 5, entries: [])
        #expect(!stats.totalSizeFormatted.isEmpty)
    }

    // MARK: - GCS Error Descriptions

    @Test("GCSError descriptions are informative")
    func errorDescriptions() {
        let listError = GCSBucketService.GCSError.listFailed(statusCode: 403)
        #expect(listError.localizedDescription.contains("403"))

        let deleteError = GCSBucketService.GCSError.deleteFailed(key: "test/key.zip", statusCode: 404)
        #expect(deleteError.localizedDescription.contains("test/key.zip"))
        #expect(deleteError.localizedDescription.contains("404"))
    }
}
