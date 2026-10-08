import Foundation
import Testing
@testable import Trio

@Suite("Nightscout URL Validator Tests") struct NightscoutURLValidatorTests {
    @Test("Valid oracle.cgmsim.com URLs are accepted")
    func testValidOracleCGMSimURLs() {
        #expect(NightscoutURLValidator.isValidNightscoutURL("https://myinstance.oracle.cgmsim.com"))
        #expect(NightscoutURLValidator.isValidNightscoutURL("https://demo-test-1.oracle.cgmsim.com"))
        #expect(NightscoutURLValidator.isValidNightscoutURL("https://patient01.oracle.cgmsim.com/"))
        #expect(NightscoutURLValidator.isValidNightscoutURL("https://MYINSTANCE.ORACLE.CGMSIM.COM"))
    }

    @Test("Valid oracle2.cgmsim.com URLs are accepted")
    func testValidOracle2CGMSimURLs() {
        #expect(NightscoutURLValidator.isValidNightscoutURL("https://myinstance.oracle2.cgmsim.com"))
        #expect(NightscoutURLValidator.isValidNightscoutURL("https://sandbox-99.oracle2.cgmsim.com"))
        #expect(NightscoutURLValidator.isValidNightscoutURL("https://demo.oracle2.cgmsim.com/"))
    }

    @Test("Non-HTTPS URLs are rejected")
    func testNonHTTPSRejected() {
        #expect(!NightscoutURLValidator.isValidNightscoutURL("http://myinstance.oracle.cgmsim.com"))
        #expect(!NightscoutURLValidator.isValidNightscoutURL("http://myinstance.oracle2.cgmsim.com"))
        #expect(!NightscoutURLValidator.isValidNightscoutURL("ftp://myinstance.oracle.cgmsim.com"))
    }

    @Test("Disallowed domains are rejected")
    func testDisallowedDomainsRejected() {
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://myinstance.herokuapp.com"))
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://myinstance.nightscout.pro"))
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://myinstance.oracle3.cgmsim.com"))
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://myinstance.cgmsim.com"))
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://google.com"))
    }

    @Test("URLs without instance subdomain are rejected")
    func testMissingInstanceRejected() {
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://oracle.cgmsim.com"))
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://oracle2.cgmsim.com"))
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://.oracle.cgmsim.com"))
    }

    @Test("Nested subdomains are rejected")
    func testNestedSubdomainsRejected() {
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://sub.myinstance.oracle.cgmsim.com"))
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://a.b.oracle2.cgmsim.com"))
    }

    @Test("Invalid instance names are rejected")
    func testInvalidInstanceNamesRejected() {
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://-myinstance.oracle.cgmsim.com"))
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://myinstance-.oracle.cgmsim.com"))
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://my_instance.oracle.cgmsim.com"))
    }

    @Test("URLs with paths other than root are rejected")
    func testNonRootPathsRejected() {
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://myinstance.oracle.cgmsim.com/api/v1"))
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://myinstance.oracle.cgmsim.com/entries.json"))
    }

    @Test("Non-standard ports, queries, and fragments are rejected")
    func testPortQueryFragmentRejected() {
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://myinstance.oracle.cgmsim.com:8080"))
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://myinstance.oracle.cgmsim.com?token=123"))
        #expect(!NightscoutURLValidator.isValidNightscoutURL("https://myinstance.oracle.cgmsim.com#status"))
    }

    @Test("Normalize trims whitespace, multiple trailing slashes, and auto-prepends https")
    func testNormalize() {
        #expect(NightscoutURLValidator.normalize("  https://myinstance.oracle.cgmsim.com///  ") == "https://myinstance.oracle.cgmsim.com")
        #expect(NightscoutURLValidator.normalize("myinstance.oracle.cgmsim.com") == "https://myinstance.oracle.cgmsim.com")
        #expect(NightscoutURLValidator.normalize("myinstance.oracle2.cgmsim.com/") == "https://myinstance.oracle2.cgmsim.com")
        #expect(NightscoutURLValidator.isValidNightscoutURL("myinstance.oracle.cgmsim.com"))
    }
}
