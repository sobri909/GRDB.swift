// TODO: make those APIs public when free association is ready.
struct FreeAssociation<Left, Right> : Association where
    Left: TableRecord,
    Right: TableRecord
{
    typealias LeftAssociated = Left
    typealias RightAssociated = Right
    
    var key: String
    
    // :nodoc:
    var request: AssociationRequest<Right>
    
    let associationMapping: AssociationMapping?

    func forKey(_ key: String) -> FreeAssociation<Left, Right> {
        return FreeAssociation(
            key: key,
            request: request,
            associationMapping: associationMapping)
    }

    // :nodoc:
    func associationMapping(_ db: Database) throws -> AssociationMapping {
        if let associationMapping = associationMapping {
            return associationMapping
        }
        return { (_,_) in nil }
    }
    
    // :nodoc:
    func mapRequest(_ transform: (AssociationRequest<Right>) -> AssociationRequest<Right>) -> FreeAssociation<Left, Right> {
        return FreeAssociation(
            key: key,
            request: transform(request),
            associationMapping: associationMapping)
    }
}

extension TableRecord {
    // TODO: Make it public if and only if we really want to build an association from any request
    static func associationTo<Right>(
        _ rightRequest: QueryInterfaceRequest<Right>,
        key: String? = nil,
        mapping: AssociationMapping? = nil)
        -> FreeAssociation<Self, Right>
        where Right: TableRecord
    {
        return FreeAssociation(
            key: key ?? defaultAssociationKey(for: Right.self),
            request: AssociationRequest(rightRequest),
            associationMapping: mapping)
    }
    
    /// TODO
    static func associationTo<Right>(
        _ right: Right.Type,
        key: String? = nil,
        mapping: AssociationMapping? = nil)
        -> FreeAssociation<Self, Right>
        where Right: TableRecord
    {
        return associationTo(Right.all(), key: key, mapping: mapping)
    }
}
