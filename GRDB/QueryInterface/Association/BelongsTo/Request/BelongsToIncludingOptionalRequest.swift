public struct BelongsToIncludingOptionalRequest<Left, Right> where
    Left: TableMapping,
    Right: TableMapping
{
    public typealias WrappedRequest = QueryInterfaceRequest<Left>
    
    let leftRequest: WrappedRequest
    let association: BelongsToAssociation<Left, Right>
}

extension BelongsToIncludingOptionalRequest : RequestDerivableWrapper {
    public func mapRequest(_ transform: (WrappedRequest) -> (WrappedRequest)) -> BelongsToIncludingOptionalRequest {
        return BelongsToIncludingOptionalRequest(
            leftRequest: transform(leftRequest),
            association: association)
    }
}

extension BelongsToIncludingOptionalRequest : TypedRequest {
    public typealias RowDecoder = JoinedPair<Left, Right?>
    
    public func prepare(_ db: Database) throws -> (SelectStatement, RowAdapter?) {
        return try prepareIncludingRequest(
            db,
            left: leftRequest.query,
            join: .left,
            right: association.rightRequest.query,
            on: association.mapping(db),
            leftScope: RowDecoder.leftScope,
            rightScope: RowDecoder.rightScope)
    }
}

extension QueryInterfaceRequest where RowDecoder: TableMapping {
    public func including<Right>(
        optional association: BelongsToAssociation<RowDecoder, Right>)
        -> BelongsToIncludingOptionalRequest<RowDecoder, Right>
    {
        return BelongsToIncludingOptionalRequest(leftRequest: self, association: association)
    }
}

extension TableMapping {
    public static func including<Right>(
        optional association: BelongsToAssociation<Self, Right>)
        -> BelongsToIncludingOptionalRequest<Self, Right>
    {
        return all().including(optional: association)
    }
}
