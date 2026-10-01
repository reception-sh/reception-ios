internal enum UserIdentity {
    /// User IDs are opaque server identifiers; Swift's canonical Unicode equivalence would merge distinct users.
    static func matches(_ first: String?, _ second: String?) -> Bool {
        guard let first, let second else { return first == nil && second == nil }
        return first.utf8.elementsEqual(second.utf8)
    }
}
