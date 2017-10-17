public struct HasManyFlatIncludingOptionalRequest<Left, Right> where
    Left: TableMapping,
    Right: TableMapping
{
    public typealias WrappedRequest = QueryInterfaceRequest<Left>
    
    let leftRequest: WrappedRequest
    let association: HasManyAssociation<Left, Right>
}

extension HasManyFlatIncludingOptionalRequest : RequestDerivableWrapper {
    public func mapRequest(_ transform: (WrappedRequest) -> (WrappedRequest)) -> HasManyFlatIncludingOptionalRequest {
        return HasManyFlatIncludingOptionalRequest(
            leftRequest: transform(leftRequest),
            association: association)
    }
}

extension HasManyFlatIncludingOptionalRequest : TypedRequest {
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
    public func flatIncluding<Right>(optional association: HasManyAssociation<RowDecoder, Right>)
        -> HasManyFlatIncludingOptionalRequest<RowDecoder, Right>
    {
        return HasManyFlatIncludingOptionalRequest(leftRequest: self, association: association)
    }
}

extension TableMapping {
    public static func flatIncluding<Right>(optional association: HasManyAssociation<Self, Right>)
        -> HasManyFlatIncludingOptionalRequest<Self, Right>
    {
        return all().flatIncluding(optional: association)
    }
}
