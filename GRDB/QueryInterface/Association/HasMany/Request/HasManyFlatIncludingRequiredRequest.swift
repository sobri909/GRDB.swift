public struct HasManyFlatIncludingRequiredRequest<Left, Right> where
    Left: TableMapping,
    Right: TableMapping
{
    public typealias WrappedRequest = QueryInterfaceRequest<Left>
    
    let leftRequest: WrappedRequest
    let association: HasManyAssociation<Left, Right>
}

extension HasManyFlatIncludingRequiredRequest : RequestDerivableWrapper {
    public func mapRequest(_ transform: (WrappedRequest) -> (WrappedRequest)) -> HasManyFlatIncludingRequiredRequest {
        return HasManyFlatIncludingRequiredRequest(
            leftRequest: transform(leftRequest),
            association: association)
    }
}

extension HasManyFlatIncludingRequiredRequest : TypedRequest {
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
    public func flatIncluding<Right>(required association: HasManyAssociation<RowDecoder, Right>)
        -> HasManyFlatIncludingRequiredRequest<RowDecoder, Right>
    {
        return HasManyFlatIncludingRequiredRequest(leftRequest: self, association: association)
    }
}

extension TableMapping {
    public static func flatIncluding<Right>(required association: HasManyAssociation<Self, Right>)
        -> HasManyFlatIncludingRequiredRequest<Self, Right>
    {
        return all().flatIncluding(required: association)
    }
}
