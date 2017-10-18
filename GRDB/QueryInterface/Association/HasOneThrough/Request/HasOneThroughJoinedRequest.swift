// TODO: consider only using left joins for this kind of query
public struct HasOneThroughJoinedRequest<MiddleAssociation, RightAssociation> where
    MiddleAssociation: AssociationToOne,
    RightAssociation: RequestDerivableWrapper, // TODO: Remove once SE-0143 is implemented
    RightAssociation: AssociationToOne,
    MiddleAssociation.RightAssociated == RightAssociation.LeftAssociated
{
    let leftRequest: QueryInterfaceRequest<MiddleAssociation.LeftAssociated>
    let joinOp: SQLJoinOperator
    let association: HasOneThroughAssociation<MiddleAssociation, RightAssociation>
}

// TODO: Derive conditional conformance to RequestDerivableWrapper once once SE-0143 is implemented
extension HasOneThroughJoinedRequest : RequestDerivableWrapper {
    public typealias WrappedRequest = QueryInterfaceRequest<MiddleAssociation.LeftAssociated>
    
    public func mapRequest(_ transform: (QueryInterfaceRequest<MiddleAssociation.LeftAssociated>) -> (QueryInterfaceRequest<MiddleAssociation.LeftAssociated>)) -> HasOneThroughJoinedRequest {
        return HasOneThroughJoinedRequest(
            leftRequest: transform(leftRequest),
            joinOp: joinOp,
            association: association)
    }
}

extension HasOneThroughJoinedRequest : TypedRequest {
    public typealias RowDecoder = MiddleAssociation.LeftAssociated
    
    public func prepare(_ db: Database) throws -> (SelectStatement, RowAdapter?) {
        // Qualify queries
        var leftQualifier = SQLSourceQualifier()
        var middleQualifier = SQLSourceQualifier()
        var rightQualifier = SQLSourceQualifier()
        let leftQuery = leftRequest.query.qualified(by: &leftQualifier)
        let middleQuery = association.middleAssociation.rightRequest.query.qualified(by: &middleQualifier)
        let rightQuery = association.rightAssociation.rightRequest.query.qualified(by: &rightQualifier)
        try [leftQualifier, middleQualifier, rightQualifier].resolveAmbiguities()
        
        // ... FROM left JOIN middle JOIN right
        let joinedSource = try leftQuery.source.join(
            joinOp,
            on: association.middleAssociation.mapping(db),
            and: middleQuery.whereExpression,
            to: middleQuery.source.join(
                joinOp,
                on: association.rightAssociation.mapping(db),
                and: rightQuery.whereExpression,
                to: rightQuery.source))
        
        return try QueryInterfaceSelectQueryDefinition(
            select: leftQuery.selection,
            isDistinct: leftQuery.isDistinct,
            from: joinedSource,
            filter: leftQuery.whereExpression,
            groupBy: leftQuery.groupByExpressions,
            orderBy: leftQuery.orderings,
            isReversed: leftQuery.isReversed,
            having: leftQuery.havingExpression,
            limit: leftQuery.limit)
            .prepare(db)
    }
}

extension QueryInterfaceRequest where RowDecoder: TableMapping {
    public func joining<MiddleAssociation, RightAssociation>(required association: HasOneThroughAssociation<MiddleAssociation, RightAssociation>)
        -> HasOneThroughJoinedRequest<MiddleAssociation, RightAssociation>
        where MiddleAssociation.LeftAssociated == RowDecoder
    {
        return HasOneThroughJoinedRequest(leftRequest: self, joinOp: .inner, association: association)
    }
    
    public func joining<MiddleAssociation, RightAssociation>(optional association: HasOneThroughAssociation<MiddleAssociation, RightAssociation>)
        -> HasOneThroughJoinedRequest<MiddleAssociation, RightAssociation>
        where MiddleAssociation.LeftAssociated == RowDecoder
    {
        return HasOneThroughJoinedRequest(leftRequest: self, joinOp: .left, association: association)
    }
}

extension TableMapping {
    public static func joining<MiddleAssociation, RightAssociation>(required association: HasOneThroughAssociation<MiddleAssociation, RightAssociation>)
        -> HasOneThroughJoinedRequest<MiddleAssociation, RightAssociation>
        where MiddleAssociation.LeftAssociated == Self
    {
        return all().joining(required: association)
    }
    
    public static func joining<MiddleAssociation, RightAssociation>(optional association: HasOneThroughAssociation<MiddleAssociation, RightAssociation>)
        -> HasOneThroughJoinedRequest<MiddleAssociation, RightAssociation>
        where MiddleAssociation.LeftAssociated == Self
    {
        return all().joining(optional: association)
    }
}
