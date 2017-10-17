public struct BelongsToIncludingRequiredRequest<Left, Right> where
    Left: TableMapping,
    Right: TableMapping
{
    public typealias WrappedRequest = QueryInterfaceRequest<Left>
    
    let leftRequest: WrappedRequest
    let association: BelongsToAssociation<Left, Right>
}

extension BelongsToIncludingRequiredRequest : RequestDerivableWrapper {
    public func mapRequest(_ transform: (WrappedRequest) -> (WrappedRequest)) -> BelongsToIncludingRequiredRequest {
        return BelongsToIncludingRequiredRequest(
            leftRequest: transform(leftRequest),
            association: association)
    }
}

extension BelongsToIncludingRequiredRequest : TypedRequest {
    public typealias RowDecoder = JoinedPair<Left, Right>
    
    public func prepare(_ db: Database) throws -> (SelectStatement, RowAdapter?) {
        return try prepareIncludingRequest(
            db,
            left: leftRequest.query,
            join: .inner,
            right: association.rightRequest.query,
            on: association.mapping(db),
            leftScope: RowDecoder.leftScope,
            rightScope: RowDecoder.rightScope)
    }
}

extension QueryInterfaceRequest where RowDecoder: TableMapping {
    public func including<Right>(
        required association: BelongsToAssociation<RowDecoder, Right>)
        -> BelongsToIncludingRequiredRequest<RowDecoder, Right>
    {
        return BelongsToIncludingRequiredRequest(leftRequest: self, association: association)
    }
}

extension TableMapping {
    public static func including<Right>(
        required association: BelongsToAssociation<Self, Right>)
        -> BelongsToIncludingRequiredRequest<Self, Right>
    {
        return all().including(required: association)
    }
}
