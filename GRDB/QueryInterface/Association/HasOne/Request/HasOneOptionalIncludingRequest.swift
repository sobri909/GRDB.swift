public struct HasOneOptionalIncludingRequest<Left, Right> where
    Left: TableMapping,
    Right: TableMapping
{
    let leftRequest: WrappedRequest
    let association: HasOneAssociation<Left, Right>
}

extension HasOneOptionalIncludingRequest : RequestDerivableWrapper {
    public typealias WrappedRequest = QueryInterfaceRequest<Left>
    
    public func mapRequest(_ transform: (WrappedRequest) -> (WrappedRequest)) -> HasOneOptionalIncludingRequest {
        return HasOneOptionalIncludingRequest(
            leftRequest: transform(leftRequest),
            association: association)
    }
}

extension HasOneOptionalIncludingRequest : TypedRequest {
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
    public func including<Right>(optional association: HasOneAssociation<RowDecoder, Right>)
        -> HasOneOptionalIncludingRequest<RowDecoder, Right>
    {
        return HasOneOptionalIncludingRequest(leftRequest: self, association: association)
    }
}

extension TableMapping {
    public static func including<Right>(optional association: HasOneAssociation<Self, Right>)
        -> HasOneOptionalIncludingRequest<Self, Right>
    {
        return all().including(optional: association)
    }
}
