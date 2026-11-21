import XCTest
@testable import GhafCore

final class AccountMatcherTests: XCTestCase {
    func testExactInstitutionAndWalletNameMatch() {
        let bank = AccountCandidate(id: UUID(), name: "Current", institution: "Mashreq", isBankAccount: true, isPrimary: false)
        XCTAssertEqual(AccountMatcher.match(bank: "Mashreq", sender: nil, candidates: [bank]), bank.id)
        let wallet = AccountCandidate(id: UUID(), name: "Ivestor", institution: nil, isBankAccount: false, isPrimary: false)
        XCTAssertEqual(AccountMatcher.match(bank: nil, sender: "iVESTOR", candidates: [wallet]), wallet.id)
    }

    func testPartialMatchesRequireReview() {
        let account = AccountCandidate(id: UUID(), name: "Main", institution: "Mashreq Bank", isBankAccount: true, isPrimary: false)
        XCTAssertNil(AccountMatcher.match(bank: "mashreq", sender: nil, candidates: [account]))
        let short = AccountCandidate(id: UUID(), name: "AD Cash", institution: "ADCB", isBankAccount: false, isPrimary: false)
        XCTAssertNil(AccountMatcher.match(bank: nil, sender: "AD", candidates: [short]))
    }

    func testPartialSubstringCannotAutoAssign() {
        let account = AccountCandidate(id: UUID(), name: "Main", institution: "Mashreq", isBankAccount: true, isPrimary: false)
        XCTAssertNil(AccountMatcher.match(bank: "Mashreq Bank", sender: nil, candidates: [account]))
    }

    func testAmbiguousPartialReturnsNil() {
        let candidates = [
            AccountCandidate(id: UUID(), name: "Mashreq One", institution: nil, isBankAccount: true, isPrimary: false),
            AccountCandidate(id: UUID(), name: "Mashreq Two", institution: nil, isBankAccount: true, isPrimary: true)
        ]
        XCTAssertNil(AccountMatcher.match(bank: "mashreq", sender: nil, candidates: candidates))
    }

    func testExactTieUsesOnlyPrimary() {
        let primary = AccountCandidate(id: UUID(), name: "Mashreq", institution: nil, isBankAccount: true, isPrimary: true)
        let other = AccountCandidate(id: UUID(), name: "Mashreq", institution: nil, isBankAccount: true, isPrimary: false)
        XCTAssertEqual(AccountMatcher.match(bank: "Mashreq", sender: nil, candidates: [primary, other]), primary.id)
        let equal = AccountCandidate(id: UUID(), name: "Mashreq", institution: nil, isBankAccount: true, isPrimary: false)
        XCTAssertNil(AccountMatcher.match(bank: "Mashreq", sender: nil, candidates: [other, equal]))
    }
}
