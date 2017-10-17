public struct HasOneIncludingRequiredRequest<Left, Right> where
    Left: TableMapping,
    Right: TableMapping
{
    let leftRequest: WrappedRequest
    let association: HasOneAssociation<Left, Right>
}

extension HasOneIncludingRequiredRequest : RequestDerivableWrapper {
    public typealias WrappedRequest = QueryInterfaceRequest<Left>
    
    public func mapRequest(_ transform: (WrappedRequest) -> (WrappedRequest)) -> HasOneIncludingRequiredRequest {
        return HasOneIncludingRequiredRequest(
            leftRequest: transform(leftRequest),
            association: association)
    }
}

extension HasOneIncludingRequiredRequest : TypedRequest {
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
        required association: HasOneAssociation<RowDecoder, Right>)
        -> HasOneIncludingRequiredRequest<RowDecoder, Right>
    {
        return HasOneIncludingRequiredRequest(leftRequest: self, association: association)
    }
}

extension TableMapping {
    public static func including<Right>(
        required association: HasOneAssociation<Self, Right>)
        -> HasOneIncludingRequiredRequest<Self, Right>
    {
        return all().including(required: association)
    }
}
