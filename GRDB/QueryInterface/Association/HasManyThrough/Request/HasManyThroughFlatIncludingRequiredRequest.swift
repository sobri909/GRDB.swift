public struct HasManyThroughFlatIncludingRequiredRequest<MiddleAssociation, RightAssociation> where
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
extension HasManyThroughFlatIncludingRequiredRequest : RequestDerivableWrapper {
    public typealias WrappedRequest = QueryInterfaceRequest<MiddleAssociation.LeftAssociated>
    
    public func mapRequest(_ transform: (WrappedRequest) -> (WrappedRequest)) -> HasManyThroughFlatIncludingRequiredRequest {
        return HasManyThroughFlatIncludingRequiredRequest(
            leftRequest: transform(leftRequest),
            joinOp: joinOp,
            association: association)
    }
}

extension HasManyThroughFlatIncludingRequiredRequest : TypedRequest {
    public typealias RowDecoder = JoinedPair<MiddleAssociation.LeftAssociated, RightAssociation.RightAssociated>
    
    public func prepare(_ db: Database) throws -> (SelectStatement, RowAdapter?) {
        return try prepareIncludingRequest(
            db,
            left: leftRequest.query,
            join: .inner,
            middle: association.middleAssociation.rightRequest.query,
            on: association.middleAssociation.mapping(db),
            join: .inner,
            right: association.rightAssociation.rightRequest.query,
            on: association.rightAssociation.mapping(db),
            leftScope: RowDecoder.leftScope,
            rightScope: RowDecoder.rightScope)
    }
}

extension QueryInterfaceRequest where RowDecoder: TableMapping {
    public func flatIncluding<MiddleAssociation, RightAssociation>(required association: HasManyThroughAssociation<MiddleAssociation, RightAssociation>)
        -> HasManyThroughFlatIncludingRequiredRequest<MiddleAssociation, RightAssociation>
        where MiddleAssociation.LeftAssociated == RowDecoder
    {
        return HasManyThroughFlatIncludingRequiredRequest(leftRequest: self, joinOp: .inner, association: association)
    }
}

extension TableMapping {
    public static func flatIncluding<MiddleAssociation, RightAssociation>(required association: HasManyThroughAssociation<MiddleAssociation, RightAssociation>)
        -> HasManyThroughFlatIncludingRequiredRequest<MiddleAssociation, RightAssociation>
        where MiddleAssociation.LeftAssociated == Self
    {
        return all().flatIncluding(required: association)
    }
}
