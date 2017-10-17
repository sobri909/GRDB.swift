public struct HasOneThroughIncludingOptionalRequest<MiddleAssociation, RightAssociation> where
    MiddleAssociation: AssociationToOne,
    RightAssociation: RequestDerivableWrapper, // TODO: Remove once SE-0143 is implemented
    RightAssociation: AssociationToOne,
    MiddleAssociation.RightAssociated == RightAssociation.LeftAssociated
{
    let leftRequest: WrappedRequest
    let association: HasOneThroughAssociation<MiddleAssociation, RightAssociation>
}

// TODO: Derive conditional conformance to RequestDerivableWrapper once once SE-0143 is implemented
extension HasOneThroughIncludingOptionalRequest : RequestDerivableWrapper {
    public typealias WrappedRequest = QueryInterfaceRequest<MiddleAssociation.LeftAssociated>
    
    public func mapRequest(_ transform: (WrappedRequest) -> (WrappedRequest)) -> HasOneThroughIncludingOptionalRequest {
        return HasOneThroughIncludingOptionalRequest(leftRequest: transform(leftRequest), association: association)
    }
}

extension HasOneThroughIncludingOptionalRequest : TypedRequest {
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
    public func including<MiddleAssociation, RightAssociation>(
        optional association: HasOneThroughAssociation<MiddleAssociation, RightAssociation>)
        -> HasOneThroughIncludingOptionalRequest<MiddleAssociation, RightAssociation>
        where MiddleAssociation.LeftAssociated == RowDecoder
    {
        return HasOneThroughIncludingOptionalRequest(leftRequest: self, association: association)
    }
}

extension TableMapping {
    public static func including<MiddleAssociation, RightAssociation>(
        optional association: HasOneThroughAssociation<MiddleAssociation, RightAssociation>)
        -> HasOneThroughIncludingOptionalRequest<MiddleAssociation, RightAssociation>
        where MiddleAssociation.LeftAssociated == Self
    {
        return all().including(optional: association)
    }
}
