public struct BelongsToOptionalIncludingRequest<Left, Right> where
    Left: TableMapping,
    Right: TableMapping
{
    public typealias WrappedRequest = QueryInterfaceRequest<Left>
    
    let leftRequest: WrappedRequest
    let association: BelongsToAssociation<Left, Right>
}

extension BelongsToOptionalIncludingRequest : RequestDerivableWrapper {
    public func mapRequest(_ transform: (WrappedRequest) -> (WrappedRequest)) -> BelongsToOptionalIncludingRequest {
        return BelongsToOptionalIncludingRequest(
            leftRequest: transform(leftRequest),
            association: association)
    }
}

extension BelongsToOptionalIncludingRequest : TypedRequest {
    public typealias RowDecoder = JoinedPair<Left, Right?>
    
    public func prepare(_ db: Database) throws -> (SelectStatement, RowAdapter?) {
        return try prepareJoinedPairRequest(
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
    public func including<Right>(optional association: BelongsToAssociation<RowDecoder, Right>)
        -> BelongsToOptionalIncludingRequest<RowDecoder, Right>
    {
        return BelongsToOptionalIncludingRequest(leftRequest: self, association: association)
    }
}

extension TableMapping {
    public static func including<Right>(optional association: BelongsToAssociation<Self, Right>)
        -> BelongsToOptionalIncludingRequest<Self, Right>
    {
        return all().including(optional: association)
    }
}
