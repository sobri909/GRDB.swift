// TODO: consider only using left joins for this kind of query
public struct HasOneJoinedRequest<Left, Right> where
    Left: TableMapping,
    Right: TableMapping
{
    let leftRequest: WrappedRequest
    let joinOp: SQLJoinOperator
    let association: HasOneAssociation<Left, Right>
}

extension HasOneJoinedRequest : RequestDerivableWrapper {
    public typealias WrappedRequest = QueryInterfaceRequest<Left>
    
    public func mapRequest(_ transform: (WrappedRequest) -> (WrappedRequest)) -> HasOneJoinedRequest {
        return HasOneJoinedRequest(
            leftRequest: transform(leftRequest),
            joinOp: joinOp,
            association: association)
    }
}

extension HasOneJoinedRequest : TypedRequest {
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
    public func joining<Right>(required association: HasOneAssociation<RowDecoder, Right>)
        -> HasOneJoinedRequest<RowDecoder, Right>
    {
        return HasOneJoinedRequest(leftRequest: self, joinOp: .inner, association: association)
    }
    
    public func joining<Right>(optional association: HasOneAssociation<RowDecoder, Right>)
        -> HasOneJoinedRequest<RowDecoder, Right>
    {
        return HasOneJoinedRequest(leftRequest: self, joinOp: .left, association: association)
    }
}

extension TableMapping {
    public static func joining<Right>(required association: HasOneAssociation<Self, Right>)
        -> HasOneJoinedRequest<Self, Right>
    {
        return all().joining(required: association)
    }
    
    public static func joining<Right>(optional association: HasOneAssociation<Self, Right>)
        -> HasOneJoinedRequest<Self, Right>
    {
        return all().joining(optional: association)
    }
}
