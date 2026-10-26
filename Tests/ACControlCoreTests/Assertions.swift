import Testing

func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(lhs == rhs, sourceLocation: sourceLocation)
}
func expectTrue(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value, sourceLocation: sourceLocation)
}
func expectFalse(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!value, sourceLocation: sourceLocation)
}
func expectNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value == nil, sourceLocation: sourceLocation)
}
func expectNotNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value != nil, sourceLocation: sourceLocation)
}
func requireValue<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) throws -> T {
    try #require(value, sourceLocation: sourceLocation)
}
func fail(_ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
    Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
}
func expectThrows<T>(_ expression: @autoclosure () throws -> T, sourceLocation: SourceLocation = #_sourceLocation,
                     handler: (any Error) -> Void = { _ in }) {
    do { _ = try expression(); fail("Expected an error", sourceLocation: sourceLocation) }
    catch { handler(error) }
}
