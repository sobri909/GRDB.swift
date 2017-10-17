public struct BelongsToJoinedRequest<Left, Right> where
    Left: TableMapping,
    Right: TableMapping
{
    public typealias WrappedRequest = QueryInterfaceRequest<Left>
    
    let leftRequest: WrappedRequest
    let joinOp: SQLJoinOperator
    let association: BelongsToAssociation<Left, Right>
}

extension BelongsToJoinedRequest : RequestDerivableWrapper {
    public func mapRequest(_ transform: (WrappedRequest) -> (WrappedRequest)) -> BelongsToJoinedRequest {
        return BelongsToJoinedRequest(
            leftRequest: transform(leftRequest),
            joinOp: joinOp,
            association: association)
    }
}

extension BelongsToJoinedRequest : TypedRequest {
    public typealias RowDecoder = Left
    
    public func prepare(_ db: Database) throws -> (SelectStatement, RowAdapter?) {
        return try prepareJoinRequest(
            db,
            left: leftRequest.query,
            join: joinOp,
            right: association.rightRequest.query,
            on: association.mapping(db))
    }
}

extension QueryInterfaceRequest where RowDecoder: TableMapping {
    public func joining<Right>(required association: BelongsToAssociation<RowDecoder, Right>)
        -> BelongsToJoinedRequest<RowDecoder, Right>
    {
        return BelongsToJoinedRequest(leftRequest: self, joinOp: .inner, association: association)
    }

    public func joining<Right>(optional association: BelongsToAssociation<RowDecoder, Right>)
        -> BelongsToJoinedRequest<RowDecoder, Right>
    {
        return BelongsToJoinedRequest(leftRequest: self, joinOp: .left, association: association)
    }
}

extension TableMapping {
    public static func joining<Right>(required association: BelongsToAssociation<Self, Right>)
        -> BelongsToJoinedRequest<Self, Right>
    {
        return all().joining(required: association)
    }
    
    public static func joining<Right>(optional association: BelongsToAssociation<Self, Right>)
        -> BelongsToJoinedRequest<Self, Right>
    {
        return all().joining(optional: association)
    }
}
