import XCTest
@testable import StashKit

final class CardMetadataTests: XCTestCase {

    // MARK: - domainOf Tests

    func testDomainOfReturnsEmptyStringForNil() {
        XCTAssertEqual(domainOf(nil), "")
    }

    func testDomainOfRemovesWwwPrefix() {
        XCTAssertEqual(domainOf("https://www.github.com/a"), "github.com")
    }

    func testDomainOfHandlesPlainDomain() {
        XCTAssertEqual(domainOf("https://github.com/a"), "github.com")
    }

    func testDomainOfReturnsEmptyStringForInvalidUrl() {
        XCTAssertEqual(domainOf("not a url"), "")
    }

    func testDomainOfHandlesSubdomains() {
        XCTAssertEqual(domainOf("https://api.github.com/a"), "api.github.com")
    }

    func testDomainOfLowerCasesHostBeforeWwwStrip() {
        XCTAssertEqual(domainOf("https://WWW.GitHub.COM/a"), "github.com")
    }

    // MARK: - repoPath Tests

    func testRepoPathExtractsOwnerAndRepo() {
        let result = repoPath("https://github.com/supabase/supabase-swift")
        XCTAssertEqual(result?.owner, "supabase")
        XCTAssertEqual(result?.repo, "supabase-swift")
    }

    func testRepoPathReturnsNilForNonRepoUrl() {
        XCTAssertNil(repoPath("https://github.com/features/copilot"))
    }

    func testRepoPathHandlesGitlab() {
        let result = repoPath("https://gitlab.com/owner/project")
        XCTAssertEqual(result?.owner, "owner")
        XCTAssertEqual(result?.repo, "project")
    }

    func testRepoPathReturnsNilForInvalidUrl() {
        XCTAssertNil(repoPath("not a url"))
    }

    func testRepoPathReturnsNilForNil() {
        XCTAssertNil(repoPath(nil))
    }

    func testRepoPathReturnsNilForPricingPage() {
        XCTAssertNil(repoPath("https://github.com/pricing/pro"))
    }

    func testRepoPathReturnsNilForNonGithubDomain() {
        XCTAssertNil(repoPath("https://example.com/owner/repo"))
    }

    func testRepoPathReturnsNilForSingleSegment() {
        XCTAssertNil(repoPath("https://github.com/owner"))
    }

    func testRepoPathRejectsGitlabNonRepoRoots() {
        XCTAssertNil(repoPath("https://gitlab.com/explore/projects"))
    }

    // MARK: - formatFileSizeChip Tests

    func testFormatFileSizeChipReturnsNilForNil() {
        XCTAssertNil(formatFileSizeChip(nil))
    }

    func testFormatFileSizeChipReturnsNilForZero() {
        XCTAssertNil(formatFileSizeChip(0))
    }

    func testFormatFileSizeChipReturnsNilForNegative() {
        XCTAssertNil(formatFileSizeChip(-100))
    }

    func testFormatFileSizeChipFormatsBytes() {
        XCTAssertEqual(formatFileSizeChip(512), "512 B")
    }

    func testFormatFileSizeChipFormatsKilobytes() {
        XCTAssertEqual(formatFileSizeChip(1024), "1.0 KB")
    }

    func testFormatFileSizeChipFormatsMegabytes() {
        XCTAssertEqual(formatFileSizeChip(1_048_576), "1.0 MB")
    }

    func testFormatFileSizeChipFormatsGigabytes() {
        XCTAssertEqual(formatFileSizeChip(1_073_741_824), "1.0 GB")
    }

    func testFormatFileSizeChipRoundsCorrectly() {
        // 1024 * 1024 * 2.5 = 2,621,440
        XCTAssertEqual(formatFileSizeChip(2_621_440), "2.5 MB")
    }

    // MARK: - formatDurationChip Tests

    func testFormatDurationChipReturnsNilForNil() {
        XCTAssertNil(formatDurationChip(nil))
    }

    func testFormatDurationChipReturnsNilForZero() {
        XCTAssertNil(formatDurationChip(0))
    }

    func testFormatDurationChipReturnsNilForNegative() {
        XCTAssertNil(formatDurationChip(-10))
    }

    func testFormatDurationChipFormatsMinutesAndSeconds() {
        XCTAssertEqual(formatDurationChip(58), "0:58")
    }

    func testFormatDurationChipFormatsWithLeadingZero() {
        XCTAssertEqual(formatDurationChip(5), "0:05")
    }

    func testFormatDurationChipFormatsHoursMinutesSeconds() {
        XCTAssertEqual(formatDurationChip(3723), "1:02:03")
    }

    func testFormatDurationChipFormatsExactHour() {
        XCTAssertEqual(formatDurationChip(3600), "1:00:00")
    }

    func testFormatDurationChipRoundsSeconds() {
        XCTAssertEqual(formatDurationChip(58.6), "0:59")
    }

    /// Data-driven crash guard: `attributes.media.duration_s` is caller-writable JSON (any JWT
    /// holder can PATCH an item's attributes blob) — a huge-but-finite value must fail soft, not
    /// trap `Int(round(seconds))` into a grid crash-loop for that user.
    func testFormatDurationChipReturnsNilForHugeFiniteValue() {
        XCTAssertNil(formatDurationChip(1e300))
    }

    func testFormatDurationChipReturnsNilForGreatestFiniteMagnitude() {
        XCTAssertNil(formatDurationChip(Double.greatestFiniteMagnitude))
    }

    // MARK: - mimeExtensionLabel Tests

    func testMimeExtensionLabelReturnsNilForNil() {
        XCTAssertNil(mimeExtensionLabel(nil))
    }

    func testMimeExtensionLabelReturnsNilForEmpty() {
        XCTAssertNil(mimeExtensionLabel(""))
    }

    func testMimeExtensionLabelHandlesDocx() {
        XCTAssertEqual(mimeExtensionLabel("application/vnd.openxmlformats-officedocument.wordprocessingml.document"), "DOCX")
    }

    func testMimeExtensionLabelHandlesPptx() {
        XCTAssertEqual(mimeExtensionLabel("application/vnd.openxmlformats-officedocument.presentationml.presentation"), "PPTX")
    }

    func testMimeExtensionLabelHandlesXlsx() {
        XCTAssertEqual(mimeExtensionLabel("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"), "XLSX")
    }

    func testMimeExtensionLabelHandlesDoc() {
        XCTAssertEqual(mimeExtensionLabel("application/msword"), "DOC")
    }

    func testMimeExtensionLabelHandlesPpt() {
        XCTAssertEqual(mimeExtensionLabel("application/vnd.ms-powerpoint"), "PPT")
    }

    func testMimeExtensionLabelHandlesXls() {
        XCTAssertEqual(mimeExtensionLabel("application/vnd.ms-excel"), "XLS")
    }

    func testMimeExtensionLabelHandlesJpg() {
        XCTAssertEqual(mimeExtensionLabel("image/jpeg"), "JPG")
    }

    func testMimeExtensionLabelHandlesSvg() {
        XCTAssertEqual(mimeExtensionLabel("image/svg+xml"), "SVG")
    }

    func testMimeExtensionLabelHandlesMov() {
        XCTAssertEqual(mimeExtensionLabel("video/quicktime"), "MOV")
    }

    func testMimeExtensionLabelHandlesM4a() {
        XCTAssertEqual(mimeExtensionLabel("audio/mp4"), "M4A")
    }

    func testMimeExtensionLabelHandlesM4aAlternative() {
        XCTAssertEqual(mimeExtensionLabel("audio/x-m4a"), "M4A")
    }

    func testMimeExtensionLabelHandlesMp3() {
        XCTAssertEqual(mimeExtensionLabel("audio/mpeg"), "MP3")
    }

    func testMimeExtensionLabelFallbackUnknownType() {
        XCTAssertEqual(mimeExtensionLabel("application/x-blorb"), "X-BLO")
    }

    func testMimeExtensionLabelFallbackMaxFiveChars() {
        XCTAssertEqual(mimeExtensionLabel("application/verylongtypename"), "VERYL")
    }

    func testMimeExtensionLabelHandlesMissingSubtype() {
        XCTAssertNil(mimeExtensionLabel("text"))
    }

    // MARK: - isPortraitAspect Tests

    func testIsPortraitAspectReturnsTrueForPortrait() {
        XCTAssertTrue(isPortraitAspect(width: 100, height: 106))
    }

    func testIsPortraitAspectReturnsFalseForLandscape() {
        XCTAssertTrue(!isPortraitAspect(width: 100, height: 105))
    }

    func testIsPortraitAspectReturnsFalseForSquare() {
        XCTAssertTrue(!isPortraitAspect(width: 100, height: 100))
    }

    func testIsPortraitAspectUsesExactThreshold() {
        // height > width * 1.05 is the threshold
        XCTAssertTrue(!isPortraitAspect(width: 100, height: 105))  // 105 is not > 105
        XCTAssertTrue(isPortraitAspect(width: 100, height: 105.1)) // 105.1 is > 105
    }
}
