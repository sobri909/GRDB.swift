public struct HasManyThroughFlatIncludingOptionalRequest<MiddleAssociation, RightAssociation> where
    MiddleAssociation: Association,
    RightAssociation: Association,
    RightAssociation: RequestDerivableWrapper, // TODO: Remove once SE-0143 is implemented
    RightAssociation.LeftAssociated == MiddleAssociation.RightAssociated
{
    let leftRequest: WrappedRequest
    let joinOp: SQLJoinOperator
    let association: HasManyThroughAssociation<MiddleAssociation, RightAssociation>
}

// TODO: Derive conditional conformance to RequestDerivableWrapper once once SE-0143 is implemented
extension HasManyThroughFlatIncludingOptionalRequest : RequestDerivableWrapper {
    public typealias WrappedRequest = QueryInterfaceRequest<MiddleAssociation.LeftAssociated>
    
    public func mapRequest(_ transform: (WrappedRequest) -> (WrappedRequest)) -> HasManyThroughFlatIncludingOptionalRequest {
        return HasManyThroughFlatIncludingOptionalRequest(
            leftRequest: transform(leftRequest),
            joinOp: joinOp,
            association: association)
    }
}

extension HasManyThroughFlatIncludingOptionalRequest : TypedRequest {
    public typealias RowDecoder = JoinedPair<MiddleAssociation.LeftAssociated, RightAssociation.RightAssociated?>
    
    public func prepare(_ db: Database) throws -> (SelectStatement, RowAdapter?) {
        return try prepareIncludingRequest(
            db,
            left: leftRequest.query,
            join: .left,
            middle: association.middleAssociation.rightRequest.query,
            on: association.middleAssociation.mapping(db),
            join: .left,
            right: association.rightAssociation.rightRequest.query,
            on: association.rightAssociation.mapping(db),
            leftScope: RowDecoder.leftScope,
            rightScope: RowDecoder.rightScope)
    }
}

extension QueryInterfaceRequest where RowDecoder: TableMapping {
    public func flatIncluding<MiddleAssociation, RightAssociation>(optional association: HasManyThroughAssociation<MiddleAssociation, RightAssociation>)
        -> HasManyThroughFlatIncludingOptionalRequest<MiddleAssociation, RightAssociation>
        where MiddleAssociation.LeftAssociated == RowDecoder
    {
        return HasManyThroughFlatIncludingOptionalRequest(leftRequest: self, joinOp: .inner, association: association)
    }
}

extension TableMapping {
    public static func flatIncluding<MiddleAssociation, RightAssociation>(optional association: HasManyThroughAssociation<MiddleAssociation, RightAssociation>)
        -> HasManyThroughFlatIncludingOptionalRequest<MiddleAssociation, RightAssociation>
        where MiddleAssociation.LeftAssociated == Self
    {
        return all().flatIncluding(optional: association)
    }
}
