import XCTest
@testable import InkYomi

/// Guards the in-app account-deletion decoding (audit finding C2): the success
/// body relies on the shared APIClient's `.convertFromSnakeCase` strategy, and
/// the 400 blockers body is decoded with a plain decoder in the view model.
final class AccountDeletionDecodingTests: XCTestCase {

    func testDeletionResponseDecodesSnakeCaseKeys() throws {
        let json = Data("""
        {
          "grace_ends_at": "2026-07-07T00:00:00.000Z",
          "books_withdrawn": 2,
          "co_author_rows_removed": 0
        }
        """.utf8)
        // Mirror the APIClient decoder configuration.
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(AccountDeletionResponse.self, from: json)
        XCTAssertEqual(response.graceEndsAt, "2026-07-07T00:00:00.000Z")
        XCTAssertEqual(response.booksWithdrawn, 2)
        XCTAssertEqual(response.coAuthorRowsRemoved, 0)
    }

    func testBlockersErrorBodyDecodes() throws {
        let json = Data("""
        {
          "error": "blockers_present",
          "blockers": [
            { "kind": "hard", "code": "active_loan_borrower", "message": "Return your borrowed books first." },
            { "kind": "hard", "code": "pending_royalties", "message": "Resolve pending royalties." }
          ]
        }
        """.utf8)
        let body = try JSONDecoder().decode(AccountDeletionBlockersError.self, from: json)
        XCTAssertEqual(body.error, "blockers_present")
        XCTAssertEqual(body.blockers?.count, 2)
        XCTAssertEqual(body.blockers?.first?.code, "active_loan_borrower")
        XCTAssertEqual(body.blockers?.first?.message, "Return your borrowed books first.")
    }
}
