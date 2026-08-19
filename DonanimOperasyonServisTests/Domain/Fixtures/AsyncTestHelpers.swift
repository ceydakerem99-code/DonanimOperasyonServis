import XCTest

/// XCTest lacks a first-class assertion for async throwing
/// expressions in earlier SDKs. This helper mirrors the shape of
/// `XCTAssertThrowsError` so tests read the same as their
/// synchronous counterparts.
///
/// Use like:
/// ```
/// await XCTAssertThrowsErrorAsync(try await useCase.execute(...)) { error in
///     XCTAssertEqual(error as? DomainError, .unauthorized(action: .createWorkOrder))
/// }
/// ```
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #file,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail(
            message().isEmpty
                ? "Expected expression to throw, but it did not."
                : message(),
            file: file,
            line: line
        )
    } catch {
        errorHandler(error)
    }
}
