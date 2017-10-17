public struct HasManyJoinedRequest<Left, Right> where
    Left: TableMapping,
    Right: TableMapping
{
    public typealias WrappedRequest = QueryInterfaceRequest<Left>
    
    let leftRequest: WrappedRequest
    let joinOp: SQLJoinOperator
    let association: HasManyAssociation<Left, Right>
}

extension HasManyJoinedRequest : RequestDerivableWrapper {
    public func mapRequest(_ transform: (WrappedRequest) -> (WrappedRequest)) -> HasManyJoinedRequest {
        return HasManyJoinedRequest(
            leftRequest: transform(leftRequest),
            joinOp: joinOp,
            association: association)
    }
}

extension HasManyJoinedRequest : TypedRequest {
    public typealias RowDecoder = JoinedPair<Left, Right>
    
    public func prepare(_ db: Database) throws -> (SelectStatement, RowAdapter?) {
        return try prepareIncludingRequest(
            db,
            left: leftRequest.query,
            join: joinOp,
            right: association.rightRequest.query,
            on: association.mapping(db),
            leftScope: RowDecoder.leftScope,
            rightScope: RowDecoder.rightScope)
    }
}

extension QueryInterfaceRequest where RowDecoder: TableMapping {
    public func joined<Right>(with association: HasManyAssociation<RowDecoder, Right>)
        -> HasManyJoinedRequest<RowDecoder, Right>
    {
        return HasManyJoinedRequest(leftRequest: self, joinOp: .inner, association: association)
    }
    
    public func joined<Right>(withOptional association: HasManyAssociation<RowDecoder, Right>)
        -> HasManyJoinedRequest<RowDecoder, Right>
    {
        return HasManyJoinedRequest(leftRequest: self, joinOp: .left, association: association)
    }
}

extension TableMapping {
    public static func joined<Right>(with association: HasManyAssociation<Self, Right>)
        -> HasManyJoinedRequest<Self, Right>
    {
        return all().joined(with: association)
    }
    
    public static func joined<Right>(withOptional association: HasManyAssociation<Self, Right>)
        -> HasManyJoinedRequest<Self, Right>
    {
        return all().joined(withOptional: association)
    }
}
