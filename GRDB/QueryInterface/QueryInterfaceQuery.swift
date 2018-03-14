struct QueryInterfaceQuery {
    var source: SQLSource
    var selection: [SQLSelectable]
    var whereExpression: SQLExpression?
    var isDistinct: Bool
    var groupByExpressions: [SQLExpression]
    var havingExpression: SQLExpression?
    var ordering: QueryOrdering
    var limit: SQLLimit?
    var rowAdapter: RowAdapter?
    
    init(
        source: SQLSource,
        selection: [SQLSelectable],
        whereExpression: SQLExpression? = nil,
        isDistinct: Bool = false,
        groupByExpressions: [SQLExpression] = [],
        havingExpression: SQLExpression? = nil,
        ordering: QueryOrdering = QueryOrdering(),
        limit: SQLLimit? = nil,
        rowAdapter: RowAdapter? = nil)
    {
        self.source = source
        self.selection = selection
        self.whereExpression = whereExpression
        self.isDistinct = isDistinct
        self.groupByExpressions = groupByExpressions
        self.havingExpression = havingExpression
        self.ordering = ordering
        self.limit = limit
        self.rowAdapter = rowAdapter
    }
    
    func sql(_ arguments: inout StatementArguments?) -> String {
        var sql = "SELECT"
        
        if isDistinct {
            sql += " DISTINCT"
        }
        
        assert(!selection.isEmpty)
        sql += " " + selection.map { $0.resultColumnSQL(&arguments) }.joined(separator: ", ")
        
        sql += " FROM " + source.sourceSQL(&arguments)
        
        if let whereExpression = whereExpression {
            sql += " WHERE " + whereExpression.expressionSQL(&arguments)
        }
        
        if !groupByExpressions.isEmpty {
            sql += " GROUP BY " + groupByExpressions.map { $0.expressionSQL(&arguments) }.joined(separator: ", ")
        }
        
        if let havingExpression = havingExpression {
            sql += " HAVING " + havingExpression.expressionSQL(&arguments)
        }
        
        let orderings = self.resolvedOrderings
        if !orderings.isEmpty {
            sql += " ORDER BY " + orderings.map { $0.orderingTermSQL(&arguments) }.joined(separator: ", ")
        }
        
        if let limit = limit {
            sql += " LIMIT " + limit.sql
        }
        
        return sql
    }
    
    func makeDeleteStatement(_ db: Database) throws -> UpdateStatement {
        guard groupByExpressions.isEmpty else {
            // Programmer error
            fatalError("Can't delete query with GROUP BY expression")
        }
        
        guard havingExpression == nil else {
            // Programmer error
            fatalError("Can't delete query with GROUP BY expression")
        }
        
        var sql = "DELETE"
        var arguments: StatementArguments? = StatementArguments()
        
        guard source.isTable else {
            fatalError("Can't delete joined query")
        }
        sql += " FROM " + source.sourceSQL(&arguments)
        
        if let whereExpression = whereExpression {
            sql += " WHERE " + whereExpression.expressionSQL(&arguments)
        }
        
        if let limit = limit {
            let orderings = self.resolvedOrderings
            if !orderings.isEmpty {
                sql += " ORDER BY " + orderings.map { $0.orderingTermSQL(&arguments) }.joined(separator: ", ")
            }
            
            if Database.sqliteCompileOptions.contains("ENABLE_UPDATE_DELETE_LIMIT") {
                sql += " LIMIT " + limit.sql
            } else {
                fatalError("Can't delete query with limit")
            }
        }
        
        let statement = try db.makeUpdateStatement(sql)
        statement.arguments = arguments!
        return statement
    }
    
    private var resolvedOrderings: [SQLOrderingTerm] {
        return ordering.resolvedOrderings
    }
    
    /// Remove ordering
    var unorderedQuery: QueryInterfaceQuery {
        var query = self
        query.ordering = QueryOrdering()
        return query
    }
    
    // MARK: Join Support
    
    var qualifier: SQLTableQualifier? {
        return source.qualifier
    }
    
    var allQualifiers: [SQLTableQualifier] {
        return source.allQualifiers
    }
    
    // Input: SELECT * FROM foo ORDER BY bar
    // Output: SELECT foo.* FROM foo ORDER BY foo.bar
    func qualified(with qualifier: inout SQLTableQualifier) -> QueryInterfaceQuery {
        let qualifiedSource = source.qualified(with: &qualifier)
        let qualifiedSelection = selection.map { $0.qualifiedSelectable(with: qualifier) }
        let qualifiedWhereExpression = whereExpression?.qualifiedExpression(with: qualifier)
        let qualifiedGroupByExpressions = groupByExpressions.map { $0.qualifiedExpression(with: qualifier) }
        let qualifiedOrdering = ordering.qualified(with: qualifier)
        let qualifiedHavingExpression = havingExpression?.qualifiedExpression(with: qualifier)
        
        return QueryInterfaceQuery(
            source: qualifiedSource,
            selection: qualifiedSelection,
            whereExpression: qualifiedWhereExpression,
            isDistinct: isDistinct,
            groupByExpressions: qualifiedGroupByExpressions,
            havingExpression: qualifiedHavingExpression,
            ordering: qualifiedOrdering,
            limit: limit,
            rowAdapter: rowAdapter)
    }
}

extension QueryInterfaceQuery {
    
    func select(_ selection: [SQLSelectable]) -> QueryInterfaceQuery {
        assert(rowAdapter == nil, "can't change selection after rowAdapter has been defined since rowAdapter relies on column offsets")
        
        // Apply qualifier if present
        let newSelection: [SQLSelectable]
        if let qualifier = qualifier {
            newSelection = selection.map { $0.qualifiedSelectable(with: qualifier) }
        } else {
            newSelection = selection
        }
        
        var query = self
        query.selection = newSelection
        return query
    }
    
    func annotate(with selection: [SQLSelectable]) -> QueryInterfaceQuery {
        assert(rowAdapter == nil, "can't change selection after rowAdapter has been defined since rowAdapter relies on column offsets")
        
        // Apply qualifier if present
        let newSelection: [SQLSelectable]
        if let qualifier = qualifier {
            newSelection = selection.map { $0.qualifiedSelectable(with: qualifier) }
        } else {
            newSelection = selection
        }
        
        var query = self
        query.selection += newSelection
        return query
    }
    
    func distinct() -> QueryInterfaceQuery {
        var query = self
        query.isDistinct = true
        return query
    }
    
    func filter(_ predicate: SQLExpressible) -> QueryInterfaceQuery {
        // Apply qualifier if present
        let newPredicate: SQLExpression
        if let qualifier = qualifier {
            newPredicate = predicate.sqlExpression.qualifiedExpression(with: qualifier)
        } else {
            newPredicate = predicate.sqlExpression
        }
        
        var query = self
        if let expression = query.whereExpression {
            query.whereExpression = expression && newPredicate
        } else {
            query.whereExpression = newPredicate
        }
        return query
    }
    
    func none() -> QueryInterfaceQuery {
        var query = self
        query.whereExpression = false.sqlExpression
        return query
    }

    func group(_ expressions: [SQLExpressible]) -> QueryInterfaceQuery {
        // Apply qualifier if present
        let newGroupByExpressions: [SQLExpression]
        if let qualifier = qualifier {
            newGroupByExpressions = expressions.map { $0.sqlExpression.qualifiedExpression(with: qualifier) }
        } else {
            newGroupByExpressions = expressions.map { $0.sqlExpression }
        }
        
        var query = self
        query.groupByExpressions = newGroupByExpressions
        return query
    }
    
    func having(_ predicate: SQLExpressible) -> QueryInterfaceQuery {
        // Apply qualifier if present
        let newPredicate: SQLExpression
        if let qualifier = qualifier {
            newPredicate = predicate.sqlExpression.qualifiedExpression(with: qualifier)
        } else {
            newPredicate = predicate.sqlExpression
        }

        var query = self
        if let havingExpression = query.havingExpression {
            query.havingExpression = havingExpression && newPredicate
        } else {
            query.havingExpression = newPredicate
        }
        return query
    }
    
    func order(_ orderings: [SQLOrderingTerm]) -> QueryInterfaceQuery {
        return order(QueryOrdering(orderings: orderings))
    }
    
    func reversed() -> QueryInterfaceQuery {
        return order(ordering.reversed())
    }
    
    private func order(_ ordering: QueryOrdering) -> QueryInterfaceQuery {
        // Apply qualifier if present
        let newOrdering: QueryOrdering
        if let qualifier = qualifier {
            newOrdering = ordering.qualified(with: qualifier)
        } else {
            newOrdering = ordering
        }
        
        var query = self
        query.ordering = newOrdering
        return query
    }
    
    func limit(_ limit: Int, offset: Int?) -> QueryInterfaceQuery {
        var query = self
        query.limit = SQLLimit(limit: limit, offset: offset)
        return query
    }
}

extension QueryInterfaceQuery {
    func prepare(_ db: Database) throws -> (SelectStatement, RowAdapter?) {
        var arguments: StatementArguments? = StatementArguments()
        let sql = self.sql(&arguments)
        let statement = try db.makeSelectStatement(sql)
        try statement.setArgumentsWithValidation(arguments!)
        return (statement, rowAdapter)
    }
    
    func fetchCount(_ db: Database) throws -> Int {
        let (statement, adapter) = try countQuery.prepare(db)
        return try Int.fetchOne(statement, adapter: adapter)!
    }
    
    /// The database region that the request looks into.
    func fetchedRegion(_ db: Database) throws -> DatabaseRegion {
        let (statement, _) = try prepare(db)
        let region = statement.fetchedRegion
        
        // Can we intersect the region with rowIds?
        //
        // Give up unless request feeds from a single database table
        guard source.isTable, let tableName = source.tableName else {
            // TODO: try harder
            return region
        }
        
        // Give up unless primary key is rowId
        let primaryKeyInfo = try db.primaryKey(tableName)
        guard primaryKeyInfo.isRowID else {
            return region
        }
        
        // Give up unless there is a where clause
        guard let whereExpression = whereExpression else {
            return region
        }
        
        // The whereExpression knows better
        guard let rowIds = whereExpression.matchedRowIds(rowIdName: primaryKeyInfo.rowIDColumn) else {
            return region
        }
        
        // Database regions are case-insensitive: use the canonical table name
        let canonicalTableName = try db.canonicalName(table: tableName)
        return region.tableIntersection(canonicalTableName, rowIds: rowIds)
    }
    
    private var countQuery: QueryInterfaceQuery {
        guard groupByExpressions.isEmpty && limit == nil else {
            // SELECT ... GROUP BY ...
            // SELECT ... LIMIT ...
            return trivialCountQuery
        }
        
        guard source.isTable else {
            // SELECT ... FROM (something which is not a table)
            return trivialCountQuery
        }
        
        assert(!selection.isEmpty)
        if selection.count == 1 {
            guard let count = self.selection[0].count(distinct: isDistinct) else {
                return trivialCountQuery
            }
            var countQuery = unorderedQuery
            countQuery.isDistinct = false
            countQuery.selection = [count.sqlSelectable]
            return countQuery
        } else {
            // SELECT [DISTINCT] expr1, expr2, ... FROM tableName ...
            
            guard !isDistinct else {
                return trivialCountQuery
            }
            
            // SELECT expr1, expr2, ... FROM tableName ...
            // ->
            // SELECT COUNT(*) FROM tableName ...
            var countQuery = unorderedQuery
            countQuery.selection = [SQLExpressionCount(AllColumns())]
            return countQuery
        }
    }
    
    // SELECT COUNT(*) FROM (self)
    private var trivialCountQuery: QueryInterfaceQuery {
        return QueryInterfaceQuery(
            source: .query(unorderedQuery),
            selection: [SQLExpressionCount(AllColumns())])
    }
}

extension QueryInterfaceQuery {
    func chaining(
        db: Database,
        chainOp: AssociationChainOperator,
        rightQuery: AssociationQuery,
        rightKey: String,
        mapping: AssociationMapping)
        throws -> QueryInterfaceQuery
    {
        var leftQualifier = SQLTableQualifier()
        var rightQualifier = SQLTableQualifier()
        
        let leftQualifiedQuery = qualified(with: &leftQualifier)
        let rightQualifiedQuery = rightQuery.qualified(with: &rightQualifier)
        
        let leftQualifiedSelection = leftQualifiedQuery.selection
        let rightQualifiedSelection = rightQualifiedQuery.ownSelection + rightQualifiedQuery.includedSelection

        let leftSelectionWidth = try leftQualifiedSelection
            .map { try $0.columnCount(db) }
            .reduce(0, +)

        let leftAdapter = leftQualifiedQuery.rowAdapter ?? RangeRowAdapter(0..<leftSelectionWidth)
        let chainedAdapter: RowAdapter
        if rightQualifiedSelection.isEmpty {
            chainedAdapter = leftAdapter
        } else if let rightAdapter = rightQualifiedQuery.rowAdapter {
            let offsettedAdapter = OffsettedAdapter(rightAdapter, offset: leftSelectionWidth)
            chainedAdapter = leftAdapter.addingScopes([rightKey: offsettedAdapter])
        } else {
            let rightOwnSelectionWidth = try rightQualifiedQuery.ownSelection
                .map { try $0.columnCount(db) }
                .reduce(0, +)
            let rightAdapter = RangeRowAdapter(leftSelectionWidth ..< leftSelectionWidth + rightOwnSelectionWidth)
            chainedAdapter = leftAdapter.addingScopes([rightKey: rightAdapter])
        }
        
        let chainedSelection = leftQualifiedSelection + rightQualifiedSelection
        
        let chainedSource = leftQualifiedQuery.source.chaining(
            db: db,
            chainOp: chainOp,
            on: mapping,
            and: rightQualifiedQuery.onExpression,
            to: rightQualifiedQuery.source)
        
        let chainedOrdering = leftQualifiedQuery.ordering.appending(rightQualifiedQuery.ordering)

        return QueryInterfaceQuery(
            source: chainedSource,
            selection: chainedSelection,
            whereExpression: leftQualifiedQuery.whereExpression,
            isDistinct: leftQualifiedQuery.isDistinct,
            groupByExpressions: leftQualifiedQuery.groupByExpressions,
            havingExpression: leftQualifiedQuery.havingExpression,
            ordering: chainedOrdering,
            limit: leftQualifiedQuery.limit,
            rowAdapter: chainedAdapter)
    }
}

// MARK: - QueryOrdering

struct QueryOrdering {
    private var items: [OrderingItem] = []
    var isReversed: Bool
    
    private enum OrderingItem {
        case orderingTerm(SQLOrderingTerm)
        case queryOrdering(QueryOrdering)
        
        func qualified(with qualifier: SQLTableQualifier) -> OrderingItem {
            switch self {
            case .orderingTerm(let orderingTerm):
                return .orderingTerm(orderingTerm.qualifiedOrdering(with: qualifier))
            case .queryOrdering(let queryOrdering):
                return .queryOrdering(queryOrdering.qualified(with: qualifier))
            }
        }
        
        func reversed() -> OrderingItem {
            switch self {
            case .orderingTerm(let orderingTerm):
                return .orderingTerm(orderingTerm.reversed)
            case .queryOrdering(let queryOrdering):
                return .queryOrdering(queryOrdering.reversed())
            }
        }
        
        var resolvedOrderings: [SQLOrderingTerm] {
            switch self {
            case .orderingTerm(let orderingTerm):
                return [orderingTerm]
            case .queryOrdering(let queryOrdering):
                return queryOrdering.resolvedOrderings
            }
        }
    }
    
    private init(items: [OrderingItem], isReversed: Bool) {
        self.items = items
        self.isReversed = isReversed
    }
    
    init() {
        self.init(
            items: [],
            isReversed: false)
    }
    
    init(orderings: [SQLOrderingTerm]) {
        self.init(
            items: orderings.map { .orderingTerm($0) },
            isReversed: false)
    }
    
    func reversed() -> QueryOrdering {
        return QueryOrdering(
            items: items,
            isReversed: !isReversed)
    }
    
    func qualified(with qualifier: SQLTableQualifier) -> QueryOrdering {
        return QueryOrdering(
            items: items.map { $0.qualified(with: qualifier) },
            isReversed: isReversed)
    }
    
    func appending(_ ordering: QueryOrdering) -> QueryOrdering {
        return QueryOrdering(
            items: items + [.queryOrdering(ordering)],
            isReversed: isReversed)
    }
    
    var resolvedOrderings: [SQLOrderingTerm] {
        if isReversed {
            return items.flatMap { $0.reversed().resolvedOrderings }
        } else {
            return items.flatMap { $0.resolvedOrderings }
        }
    }
}

// MARK: - SQLSource

enum SQLJoinOperator : String {
    case inner = "JOIN"
    case left = "LEFT JOIN"
}

struct SQLSource {
    private enum Origin {
        case table(tableName: String, qualifier: SQLTableQualifier?)
        indirect case query(QueryInterfaceQuery)
        
        var qualifier: SQLTableQualifier? {
            switch self {
            case .table(_, let qualifier):
                return qualifier
            case .query(let query):
                return query.qualifier
            }
        }
        
        func sql(_ arguments: inout StatementArguments?) -> String {
            switch self {
            case .table(let tableName, let qualifier):
                if let alias = qualifier?.alias, alias != tableName {
                    return "\(tableName.quotedDatabaseIdentifier) \(alias.quotedDatabaseIdentifier)"
                } else {
                    return "\(tableName.quotedDatabaseIdentifier)"
                }
            case .query(let query):
                return "(\(query.sql(&arguments)))"
            }
        }
        
        func qualified(with qualifier: inout SQLTableQualifier) -> Origin {
            switch self {
            case .table(let tableName, let oldQualifier):
                if let oldQualifier = oldQualifier {
                    qualifier = oldQualifier
                    return self
                } else {
                    qualifier.tableName = tableName
                    return .table(
                        tableName: tableName,
                        qualifier: qualifier)
                }
            case .query(let query):
                return .query(query.qualified(with: &qualifier))
            }
        }
    }
    
    private struct Join {
        let chainOp: AssociationChainOperator
        let tableName: String
        let qualifier: SQLTableQualifier
        let onExpression: SQLExpression?
        let joins: [Join]
        
        func sql(_ arguments: inout StatementArguments?, fromOptionalParent: Bool) -> String {
            let joinOp: SQLJoinOperator
            switch chainOp {
            case .optional:
                joinOp = .left
            case .required:
                if fromOptionalParent {
                    // TODO: chainOptionalRequired
                    fatalError("Not implemented: chaining a required association behind an optional association")
                }
                joinOp = .inner
            }
            
            var sql = joinOp.rawValue
            
            if let alias = qualifier.alias, alias != tableName {
                sql += " \(tableName.quotedDatabaseIdentifier) \(alias.quotedDatabaseIdentifier)"
            } else {
                sql += " \(tableName.quotedDatabaseIdentifier)"
            }
            
            if let onExpression = onExpression {
                sql += " ON " + onExpression.expressionSQL(&arguments)
            }
            
            let isOptional = fromOptionalParent || joinOp == .left
            return ([sql] + joins.map { $0.sql(&arguments, fromOptionalParent: isOptional) }).joined(separator: " ")
        }
        
        var allQualifiers: [SQLTableQualifier] {
            return [qualifier] + joins.flatMap { $0.allQualifiers }
        }
    }
    
    private let origin: Origin
    private let joins: [Join]
    
    /// True if source is a simple table
    var isTable: Bool {
        switch origin {
        case .table:
            return joins.isEmpty
        default:
            return false
        }
    }
    
    /// An alias or an actual table name
    var qualifiedName: String {
        switch origin {
        case .table(let tableName, let qualifier):
            return qualifier?.qualifiedName ?? tableName
        case .query(let query):
            return query.source.qualifiedName
        }
    }
    
    /// An actual table name, not an alias
    var tableName: String? {
        switch origin {
        case .table(let tableName, _):
            return tableName
        case .query(let query):
            return query.source.tableName
        }
    }
    
    var qualifier: SQLTableQualifier? {
        return origin.qualifier
    }
    
    var allQualifiers: [SQLTableQualifier] {
        guard let qualifier = origin.qualifier else {
            return []
        }
        return [qualifier] + joins.flatMap { $0.allQualifiers }
    }
    
    static func table(_ tableName: String) -> SQLSource {
        return SQLSource(
            origin: .table(tableName: tableName, qualifier: nil),
            joins: [])
    }
    
    static func query(_ query: QueryInterfaceQuery) -> SQLSource {
        return SQLSource(
            origin: .query(query),
            joins: [])
    }
    
    // - precondition: sources are qualified
    func chaining(
        db: Database,
        chainOp: AssociationChainOperator,
        on mapping: AssociationMapping,
        and andExpression: SQLExpression?,
        to right: SQLSource) -> SQLSource
    {
        guard case .table(_, let lq) = origin, let leftQualifier = lq else {
            fatalError("left query is not qualified")
        }
        guard case .table(let rightTableName, let rq) = right.origin, let rightQualifier = rq else {
            fatalError("right query is not qualified")
        }
        
        let leftAlias = TableAlias(qualifier: leftQualifier)
        let rightAlias = TableAlias(qualifier: rightQualifier)
        let mappingExpression = mapping(leftAlias, rightAlias)?.sqlExpression
        
        let joinExpression = SQLBinaryOperator.and.join([mappingExpression, andExpression].compactMap { $0 })

        let newJoin = Join(
            chainOp: chainOp,
            tableName: rightTableName,
            qualifier: rightQualifier,
            onExpression: joinExpression,
            joins: right.joins)
        
        return SQLSource(
            origin: origin,
            joins: joins + [newJoin])
    }
    
    func sourceSQL(_ arguments: inout StatementArguments?) -> String {
        return ([origin.sql(&arguments)] + joins.map { $0.sql(&arguments, fromOptionalParent: false) }).joined(separator: " ")
    }
    
    func qualified(with qualifier: inout SQLTableQualifier) -> SQLSource {
        return SQLSource(origin: origin.qualified(with: &qualifier), joins: joins)
    }
}

struct SQLLimit {
    let limit: Int
    let offset: Int?
    
    var sql: String {
        if let offset = offset {
            return "\(limit) OFFSET \(offset)"
        } else {
            return "\(limit)"
        }
    }
}

extension SQLCount {
    var sqlSelectable: SQLSelectable {
        switch self {
        case .all:
            return SQLExpressionCount(AllColumns())
        case .distinct(let expression):
            return SQLExpressionCountDistinct(expression)
        }
    }
}
