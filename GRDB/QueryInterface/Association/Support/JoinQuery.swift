// SELECT left.*
// FROM left
// JOIN right
func prepareJoinRequest(
    _ db: Database,
    left leftQuery: QueryInterfaceSelectQueryDefinition,
    join joinOp: SQLJoinOperator,
    right rightQuery: QueryInterfaceSelectQueryDefinition,
    on mapping: [(left: String, right: String)]) throws
    -> (SelectStatement, RowAdapter?)
{
    // Qualify queries
    var leftQualifier = SQLSourceQualifier()
    var rightQualifier = SQLSourceQualifier()
    let leftQuery = leftQuery.qualified(by: &leftQualifier)
    let rightQuery = rightQuery.qualified(by: &rightQualifier)
    try [leftQualifier, rightQualifier].resolveAmbiguities()
    
    // ... FROM left JOIN right
    let joinedSource = leftQuery.source.join(
        joinOp,
        on: mapping,
        and: rightQuery.whereExpression,
        to: rightQuery.source)
    
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

// SELECT left.*, right.*
// FROM left
// JOIN right
func prepareIncludingRequest(
    _ db: Database,
    left leftQuery: QueryInterfaceSelectQueryDefinition,
    join joinOp: SQLJoinOperator,
    right rightQuery: QueryInterfaceSelectQueryDefinition,
    on mapping: [(left: String, right: String)],
    leftScope: String,
    rightScope: String) throws
    -> (SelectStatement, RowAdapter?)
{
    // Qualify queries
    var leftQualifier = SQLSourceQualifier()
    var rightQualifier = SQLSourceQualifier()
    let leftQuery = leftQuery.qualified(by: &leftQualifier)
    let rightQuery = rightQuery.qualified(by: &rightQualifier)
    try [leftQualifier, rightQualifier].resolveAmbiguities()
    
    // SELECT left.*, right.*
    let joinedSelection = leftQuery.selection + rightQuery.selection
    
    // ... FROM left JOIN right
    let joinedSource = leftQuery.source.join(
        joinOp,
        on: mapping,
        and: rightQuery.whereExpression,
        to: rightQuery.source)
    
    // ORDER BY left.***, right.***
    let joinedOrderings = leftQuery.queryOrderings + rightQuery.queryOrderings
    
    // Define row scopes
    let leftCount = try leftQuery.numberOfColumns(db)
    let rightCount = try rightQuery.numberOfColumns(db)
    let joinedAdapter = ScopeAdapter([
        // Left columns start at index 0
        leftScope: RangeRowAdapter(0..<leftCount),
        // Right columns start after left columns
        rightScope: RangeRowAdapter(leftCount..<(leftCount + rightCount))])
    
    return try QueryInterfaceSelectQueryDefinition(
        select: joinedSelection,
        isDistinct: leftQuery.isDistinct,
        from: joinedSource,
        filter: leftQuery.whereExpression,
        groupBy: leftQuery.groupByExpressions,
        orderBy: joinedOrderings,
        isReversed: false,
        having: leftQuery.havingExpression,
        limit: leftQuery.limit)
        .adapted(joinedAdapter)
        .prepare(db)
}

// SELECT left.*, right.*
// FROM left
// JOIN middle
// JOIN right
func prepareIncludingRequest(
    _ db: Database,
    left leftQuery: QueryInterfaceSelectQueryDefinition,
    join middleJoinOp: SQLJoinOperator,
    middle middleQuery: QueryInterfaceSelectQueryDefinition,
    on middleMapping: [(left: String, right: String)],
    join rightJoinOp: SQLJoinOperator,
    right rightQuery: QueryInterfaceSelectQueryDefinition,
    on rightMapping: [(left: String, right: String)],
    leftScope: String,
    rightScope: String) throws
    -> (SelectStatement, RowAdapter?)
{
    // Qualify queries
    var leftQualifier = SQLSourceQualifier()
    var middleQualifier = SQLSourceQualifier()
    var rightQualifier = SQLSourceQualifier()
    let leftQuery = leftQuery.qualified(by: &leftQualifier)
    let middleQuery = middleQuery.qualified(by: &middleQualifier)
    let rightQuery = rightQuery.qualified(by: &rightQualifier)
    try [leftQualifier, middleQualifier, rightQualifier].resolveAmbiguities()
    
    // SELECT left.*, right.*
    let joinedSelection = leftQuery.selection + rightQuery.selection
    
    // ... FROM left JOIN middle JOIN right
    let joinedSource = leftQuery.source.join(
        middleJoinOp,
        on: middleMapping,
        and: middleQuery.whereExpression,
        to: middleQuery.source.join(
            rightJoinOp,
            on: rightMapping,
            and: rightQuery.whereExpression,
            to: rightQuery.source))
    
    // ORDER BY left.***, right.***
    let joinedOrderings = leftQuery.queryOrderings + rightQuery.queryOrderings
    
    // Define row scopes
    let leftCount = try leftQuery.numberOfColumns(db)
    let rightCount = try rightQuery.numberOfColumns(db)
    let joinedAdapter = ScopeAdapter([
        // Left columns start at index 0
        leftScope: RangeRowAdapter(0..<leftCount),
        // Right columns start after left columns
        rightScope: RangeRowAdapter(leftCount..<(leftCount + rightCount))])
    
    return try QueryInterfaceSelectQueryDefinition(
        select: joinedSelection,
        isDistinct: leftQuery.isDistinct,
        from: joinedSource,
        filter: leftQuery.whereExpression,
        groupBy: leftQuery.groupByExpressions,
        orderBy: joinedOrderings,
        isReversed: false,
        having: leftQuery.havingExpression,
        limit: leftQuery.limit)
        .adapted(joinedAdapter)
        .prepare(db)
}
