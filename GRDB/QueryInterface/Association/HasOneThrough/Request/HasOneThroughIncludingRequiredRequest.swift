public struct HasOneThroughIncludingRequiredRequest<MiddleAssociation, RightAssociation> where
    MiddleAssociation: AssociationToOne,
    RightAssociation: RequestDerivableWrapper, // TODO: Remove once SE-0143 is implemented
    RightAssociation: AssociationToOne,
    MiddleAssociation.RightAssociated == RightAssociation.LeftAssociated
{
    let leftRequest: QueryInterfaceRequest<MiddleAssociation.LeftAssociated>
    let association: HasOneThroughAssociation<MiddleAssociation, RightAssociation>
}

// TODO: Derive conditional conformance to RequestDerivableWrapper once once SE-0143 is implemented
extension HasOneThroughIncludingRequiredRequest : RequestDerivableWrapper {
    public typealias WrappedRequest = QueryInterfaceRequest<MiddleAssociation.LeftAssociated>
    
    public func mapRequest(_ transform: (QueryInterfaceRequest<MiddleAssociation.LeftAssociated>) -> (QueryInterfaceRequest<MiddleAssociation.LeftAssociated>)) -> HasOneThroughIncludingRequiredRequest {
        return HasOneThroughIncludingRequiredRequest(leftRequest: transform(leftRequest), association: association)
    }
}

extension HasOneThroughIncludingRequiredRequest : TypedRequest {
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
    public func including<MiddleAssociation, RightAssociation>(
        required association: HasOneThroughAssociation<MiddleAssociation, RightAssociation>)
        -> HasOneThroughIncludingRequiredRequest<MiddleAssociation, RightAssociation>
        where MiddleAssociation.LeftAssociated == RowDecoder
    {
        return HasOneThroughIncludingRequiredRequest(leftRequest: self, association: association)
    }
}

extension TableMapping {
    public static func including<MiddleAssociation, RightAssociation>(
        required association: HasOneThroughAssociation<MiddleAssociation, RightAssociation>)
        -> HasOneThroughIncludingRequiredRequest<MiddleAssociation, RightAssociation>
        where MiddleAssociation.LeftAssociated == Self
    {
        return all().including(required: association)
    }
}
