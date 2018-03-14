/// A QueryInterfaceRequest describes an SQL query.
///
/// See https://github.com/groue/GRDB.swift#the-query-interface
public struct QueryInterfaceRequest<T> {
    // A QueryInterfaceRequest can turn into a QueryInterfaceQuery once given
    // a database connection.
    private var queryPromise: DatabasePromise<QueryInterfaceQuery>
    
    // Processing of the query filters, orderings, selection...
    private var transforms: [DatabaseTransform<QueryInterfaceQuery>] = []
    
    // Processing of the query chains. Must happen after selection has been
    // defined, so that the selected rows have a fixed layout on which we can
    // define row scopes that help consuming joined rows.
    private var chainTransforms: [DatabaseTransform<QueryInterfaceQuery>] = []
    
    init(queryPromise: @escaping DatabasePromise<QueryInterfaceQuery>) {
        self.queryPromise = queryPromise
    }
    
    init(query: QueryInterfaceQuery) {
        self.init(queryPromise: { _ in query })
    }
    
    func query(_ db: Database) throws -> QueryInterfaceQuery {
        var query = try queryPromise(db)
        
        // Filters, orderings, selection...
        query = try transforms.reduce(query) { try $1(db, $0) }
        
        // Query chains
        query = try chainTransforms.reduce(query) { try $1(db, $0) }
        
        // Resolve table qualifiers ambiguities
        query.allQualifiers.resolveAmbiguities()
        
        return query
    }
    
    func mapQuery(_ transform: @escaping DatabaseTransform<QueryInterfaceQuery>) -> QueryInterfaceRequest<T> {
        var request = self
        request.transforms.append(transform)
        return request
    }
    
    func mapQueryChain(_ transform: @escaping DatabaseTransform<QueryInterfaceQuery>) -> QueryInterfaceRequest<T> {
        var request = self
        request.chainTransforms.append(transform)
        return request
    }
}

extension QueryInterfaceRequest : FetchRequest {
    public typealias RowDecoder = T
    
    /// A tuple that contains a prepared statement that is ready to be
    /// executed, and an eventual row adapter.
    ///
    /// - parameter db: A database connection.
    ///
    /// :nodoc:
    public func prepare(_ db: Database) throws -> (SelectStatement, RowAdapter?) {
        return try query(db).prepare(db)
    }
    
    /// The number of rows fetched by the request.
    ///
    /// - parameter db: A database connection.
    ///
    /// :nodoc:
    public func fetchCount(_ db: Database) throws -> Int {
        return try query(db).fetchCount(db)
    }
    
    /// The database region that the request looks into.
    ///
    /// :nodoc:
    public func fetchedRegion(_ db: Database) throws -> DatabaseRegion {
        return try query(db).fetchedRegion(db)
    }
}

extension QueryInterfaceRequest : SelectionRequest, FilteredRequest, AggregatingRequest, OrderedRequest {
    
    // MARK: Request Derivation
    
    /// Creates a request with a new net of selected columns.
    ///
    ///     // SELECT id, email FROM players
    ///     var request = Player.all()
    ///     request = request.select([Column("id"), Column("email")])
    ///
    /// Any previous selection is replaced:
    ///
    ///     // SELECT email FROM players
    ///     request
    ///         .select([Column("id")])
    ///         .select([Column("email")])
    public func select(_ selection: [SQLSelectable]) -> QueryInterfaceRequest<T> {
        return mapQuery { (_, query) in query.select(selection) }
    }
    
    // TODO: make public when annotations are ready.
//    /// Creates a request with columns appended to the selection.
//    public func annotate(with selection: [SQLSelectable]) -> QueryInterfaceRequest<T> {
//        return mapQuery { (_, query) in query.annotate(with: selection) }
//    }

    /// Creates a request which returns distinct rows.
    ///
    ///     // SELECT DISTINCT * FROM players
    ///     var request = Player.all()
    ///     request = request.distinct()
    ///
    ///     // SELECT DISTINCT name FROM players
    ///     var request = Player.select(Column("name"))
    ///     request = request.distinct()
    public func distinct() -> QueryInterfaceRequest<T> {
        return mapQuery { (_, query) in query.distinct() }
    }
    
    /// Creates a request with the provided *predicate* added to the
    /// eventual set of already applied predicates.
    ///
    ///     // SELECT * FROM players WHERE email = 'arthur@example.com'
    ///     var request = Player.all()
    ///     request = request.filter(Column("email") == "arthur@example.com")
    public func filter(_ predicate: SQLExpressible) -> QueryInterfaceRequest<T> {
        return mapQuery { (_, query) in query.filter(predicate) }
    }
    
    /// Creates a request that matches nothing.
    ///
    ///     // SELECT * FROM players WHERE 0
    ///     var request = Player.all()
    ///     request = request.none()
    public func none() -> QueryInterfaceRequest<T> {
        return mapQuery { (_, query) in query.none() }
    }

    /// Creates a request grouped according to *expressions*.
    public func group(_ expressions: [SQLExpressible]) -> QueryInterfaceRequest<T> {
        return mapQuery { (_, query) in query.group(expressions) }
    }
    
    /// Creates a request with the provided *predicate* added to the
    /// eventual set of already applied predicates.
    public func having(_ predicate: SQLExpressible) -> QueryInterfaceRequest<T> {
        return mapQuery { (_, query) in query.having(predicate) }
    }
    
    /// Creates a request with the provided *orderings*.
    ///
    ///     // SELECT * FROM players ORDER BY name
    ///     var request = Player.all()
    ///     request = request.order([Column("name")])
    ///
    /// Any previous ordering is replaced:
    ///
    ///     // SELECT * FROM players ORDER BY name
    ///     request
    ///         .order([Column("email")])
    ///         .reversed()
    ///         .order([Column("name")])
    public func order(_ orderings: [SQLOrderingTerm]) -> QueryInterfaceRequest<T> {
        return mapQuery { (_, query) in query.order(orderings) }
    }
    
    /// Creates a request that reverses applied orderings. If no ordering
    /// was applied, the returned request is identical.
    ///
    ///     // SELECT * FROM players ORDER BY name DESC
    ///     var request = Player.all().order(Column("name"))
    ///     request = request.reversed()
    ///
    ///     // SELECT * FROM players
    ///     var request = Player.all()
    ///     request = request.reversed()
    public func reversed() -> QueryInterfaceRequest<T> {
        return mapQuery { (_, query) in query.reversed() }
    }
    
    /// Creates a request which fetches *limit* rows, starting
    /// at *offset*.
    ///
    ///     // SELECT * FROM players LIMIT 1
    ///     var request = Player.all()
    ///     request = request.limit(1)
    public func limit(_ limit: Int, offset: Int? = nil) -> QueryInterfaceRequest<T> {
        return mapQuery { (_, query) in query.limit(limit, offset: offset) }
    }
    
    /// Creates a request that allows you to define unambiguous expressions
    /// based on the fetched record.
    ///
    /// In the example below, the "team.avgScore < player.score" condition in
    /// the ON clause could be not achieved without table aliases.
    ///
    ///     struct Player: TableRecord {
    ///         static let team = belongsTo(Team.self)
    ///     }
    ///
    ///     // SELECT player.*, team.*
    ///     // JOIN team ON ... AND team.avgScore < player.score
    ///     let playerAlias = TableAlias()
    ///     let request = Player
    ///         .all()
    ///         .aliased(playerAlias)
    ///         .including(required: Player.team.filter(Column("avgScore") < playerAlias[Column("score")])
    public func aliased(_ alias: TableAlias) -> QueryInterfaceRequest {
        return mapQuery { (_, query) in
            let userProvidedAlias = alias.userProvidedAlias
            defer {
                // Allow user to explicitely rename (TODO: test)
                alias.userProvidedAlias = userProvidedAlias
            }
            return query.qualified(with: &alias.qualifier)
        }
    }
}

extension QueryInterfaceRequest where T: TableRecord {
    
    /// Creates a request with the provided primary key *predicate*.
    ///
    ///     // SELECT * FROM players WHERE id = 1
    ///     var request = Player.all()
    ///     request = request.filter(key: 1)
    public func filter<PrimaryKeyType: DatabaseValueConvertible>(key: PrimaryKeyType?) -> QueryInterfaceRequest<T> {
        guard let key = key else {
            return T.none()
        }
        
        return filter(keys: [key])
    }

    /// Creates a request with the provided primary key *predicate*.
    ///
    ///     // SELECT * FROM players WHERE id IN (1, 2, 3)
    ///     var request = Player.all()
    ///     request = request.filter(keys: [1, 2, 3])
    public func filter<Sequence: Swift.Sequence>(keys: Sequence) -> QueryInterfaceRequest<T> where Sequence.Element: DatabaseValueConvertible {
        let keys = Array(keys)
        let makePredicate: (Column) -> SQLExpression
        switch keys.count {
        case 0:
            return T.none()
        case 1:
            makePredicate = { $0 == keys[0] }
        default:
            makePredicate = { keys.contains($0) }
        }
        
        return mapQuery { (db, query) in
            let primaryKey = try db.primaryKey(T.databaseTableName)
            GRDBPrecondition(primaryKey.columns.count == 1, "Requesting by key requires a single-column primary key in the table \(T.databaseTableName)")
            let keysPredicate = makePredicate(Column(primaryKey.columns[0]))
            return query.filter(keysPredicate)
        }
    }
    
    /// Creates a request with the provided primary key *predicate*.
    ///
    ///     // SELECT * FROM passports WHERE personId = 1 AND countryCode = 'FR'
    ///     var request = Player.all()
    ///     request = request.filter(key: ["personId": 1, "countryCode": "FR"])
    ///
    /// When executed, this request raises a fatal error if there is no unique
    /// index on the key columns.
    public func filter(key: [String: DatabaseValueConvertible?]?) -> QueryInterfaceRequest<T> {
        guard let key = key else {
            return T.none()
        }
        
        return filter(keys: [key])
    }
    
    /// Creates a request with the provided primary key *predicate*.
    ///
    ///     // SELECT * FROM passports WHERE (personId = 1 AND countryCode = 'FR') OR ...
    ///     let request = Passport.filter(keys: [["personId": 1, "countryCode": "FR"], ...])
    ///
    /// When executed, this request raises a fatal error if there is no unique
    /// index on the key columns.
    public func filter(keys: [[String: DatabaseValueConvertible?]]) -> QueryInterfaceRequest<T> {
        guard !keys.isEmpty else {
            return T.none()
        }
        
        return mapQuery { (db, query) in
            let keyPredicates: [SQLExpression] = try keys.map { key in
                // Prevent filter(db, keys: [[:]])
                GRDBPrecondition(!key.isEmpty, "Invalid empty key dictionary")
                
                // Prevent filter(keys: [["foo": 1, "bar": 2]]) where
                // ("foo", "bar") is not a unique key (primary key or columns of a
                // unique index)
                guard let orderedColumns = try db.columnsForUniqueKey(key.keys, in: T.databaseTableName) else {
                    fatalError("table \(T.databaseTableName) has no unique index on column(s) \(key.keys.sorted().joined(separator: ", "))")
                }
                
                let lowercaseOrderedColumns = orderedColumns.map { $0.lowercased() }
                let columnPredicates: [SQLExpression] = key
                    // Sort key columns in the same order as the unique index
                    .sorted { (kv1, kv2) in lowercaseOrderedColumns.index(of: kv1.0.lowercased())! < lowercaseOrderedColumns.index(of: kv2.0.lowercased())! }
                    .map { (column, value) in Column(column) == value }
                return SQLBinaryOperator.and.join(columnPredicates)! // not nil because columnPredicates is not empty
            }
            
            let keysPredicate = SQLBinaryOperator.or.join(keyPredicates)! // not nil because keyPredicates is not empty
            return query.filter(keysPredicate)
        }
    }
}

extension QueryInterfaceRequest where RowDecoder: MutablePersistableRecord {
    
    // MARK: Deleting
    
    /// Deletes matching rows; returns the number of deleted rows.
    ///
    /// - parameter db: A database connection.
    /// - returns: The number of deleted rows
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    @discardableResult
    public func deleteAll(_ db: Database) throws -> Int {
        try query(db).makeDeleteStatement(db).execute()
        return db.changesCount
    }
}

extension TableRecord {
    
    // MARK: Fetch Requests
    
    /// Creates a request which fetches all records.
    ///
    ///     // SELECT * FROM players
    ///     let request = Player.all()
    ///
    /// The selection defaults to all columns. This default can be changed for
    /// all requests by the `TableRecord.databaseSelection` property, or
    /// for individual requests with the `TableRecord.select` method.
    public static func all() -> QueryInterfaceRequest<Self> {
        let query = QueryInterfaceQuery(
            source: .table(databaseTableName),
            selection: databaseSelection)
        return QueryInterfaceRequest(query: query)
    }
    
    /// Creates a request which fetches no record.
    public static func none() -> QueryInterfaceRequest<Self> {
        return all().none()
    }
    
    /// Creates a request which selects *selection*.
    ///
    ///     // SELECT id, email FROM players
    ///     let request = Player.select(Column("id"), Column("email"))
    public static func select(_ selection: SQLSelectable...) -> QueryInterfaceRequest<Self> {
        return all().select(selection)
    }
    
    /// Creates a request which selects *selection*.
    ///
    ///     // SELECT id, email FROM players
    ///     let request = Player.select([Column("id"), Column("email")])
    public static func select(_ selection: [SQLSelectable]) -> QueryInterfaceRequest<Self> {
        return all().select(selection)
    }
    
    // TODO: make public when annotations are ready.
//    /// Creates a request with columns appended to the default selection.
//    ///
//    /// The selection defaults to all columns. This default can be changed for
//    /// all requests by the `TableRecord.databaseSelection` property, or
//    /// for individual requests with the `TableRecord.select` method.
//    public static func annotate(with selection: SQLSelectable...) -> QueryInterfaceRequest<Self> {
//        return all().annotate(with: selection)
//    }

    // TODO: make public when annotations are ready.
//    /// Creates a request with columns appended to the default selection.
//    ///
//    /// The selection defaults to all columns. This default can be changed for
//    /// all requests by the `TableRecord.databaseSelection` property, or
//    /// for individual requests with the `TableRecord.select` method.
//    public static func annotate(with selection: [SQLSelectable]) -> QueryInterfaceRequest<Self> {
//        return all().annotate(with: selection)
//    }

    /// Creates a request which selects *sql*.
    ///
    ///     // SELECT id, email FROM players
    ///     let request = Player.select(sql: "id, email")
    public static func select(sql: String, arguments: StatementArguments? = nil) -> QueryInterfaceRequest<Self> {
        return all().select(sql: sql, arguments: arguments)
    }
    
    /// Creates a request with the provided *predicate*.
    ///
    ///     // SELECT * FROM players WHERE email = 'arthur@example.com'
    ///     let request = Player.filter(Column("email") == "arthur@example.com")
    ///
    /// The selection defaults to all columns. This default can be changed for
    /// all requests by the `TableRecord.databaseSelection` property, or
    /// for individual requests with the `TableRecord.select` method.
    public static func filter(_ predicate: SQLExpressible) -> QueryInterfaceRequest<Self> {
        return all().filter(predicate)
    }
    
    /// Creates a request with the provided primary key *predicate*.
    ///
    ///     // SELECT * FROM players WHERE id = 1
    ///     let request = Player.filter(key: 1)
    ///
    /// The selection defaults to all columns. This default can be changed for
    /// all requests by the `TableRecord.databaseSelection` property, or
    /// for individual requests with the `TableRecord.select` method.
    public static func filter<PrimaryKeyType: DatabaseValueConvertible>(key: PrimaryKeyType?) -> QueryInterfaceRequest<Self> {
        return all().filter(key: key)
    }
    
    /// Creates a request with the provided primary key *predicate*.
    ///
    ///     // SELECT * FROM players WHERE id IN (1, 2, 3)
    ///     let request = Player.filter(keys: [1, 2, 3])
    ///
    /// The selection defaults to all columns. This default can be changed for
    /// all requests by the `TableRecord.databaseSelection` property, or
    /// for individual requests with the `TableRecord.select` method.
    public static func filter<Sequence: Swift.Sequence>(keys: Sequence) -> QueryInterfaceRequest<Self> where Sequence.Element: DatabaseValueConvertible {
        return all().filter(keys: keys)
    }
    
    /// Creates a request with the provided primary key *predicate*.
    ///
    ///     // SELECT * FROM passports WHERE personId = 1 AND countryCode = 'FR'
    ///     let request = Passport.filter(key: ["personId": 1, "countryCode": "FR"])
    ///
    /// When executed, this request raises a fatal error if there is no unique
    /// index on the key columns.
    ///
    /// The selection defaults to all columns. This default can be changed for
    /// all requests by the `TableRecord.databaseSelection` property, or
    /// for individual requests with the `TableRecord.select` method.
    public static func filter(key: [String: DatabaseValueConvertible?]?) -> QueryInterfaceRequest<Self> {
        return all().filter(key: key)
    }
    
    /// Creates a request with the provided primary key *predicate*.
    ///
    ///     // SELECT * FROM passports WHERE (personId = 1 AND countryCode = 'FR') OR ...
    ///     let request = Passport.filter(keys: [["personId": 1, "countryCode": "FR"], ...])
    ///
    /// When executed, this request raises a fatal error if there is no unique
    /// index on the key columns.
    ///
    /// The selection defaults to all columns. This default can be changed for
    /// all requests by the `TableRecord.databaseSelection` property, or
    /// for individual requests with the `TableRecord.select` method.
    public static func filter(keys: [[String: DatabaseValueConvertible?]]) -> QueryInterfaceRequest<Self> {
        return all().filter(keys: keys)
    }
    
    /// Creates a request with the provided *predicate*.
    ///
    ///     // SELECT * FROM players WHERE email = 'arthur@example.com'
    ///     let request = Player.filter(sql: "email = ?", arguments: ["arthur@example.com"])
    ///
    /// The selection defaults to all columns. This default can be changed for
    /// all requests by the `TableRecord.databaseSelection` property, or
    /// for individual requests with the `TableRecord.select` method.
    public static func filter(sql: String, arguments: StatementArguments? = nil) -> QueryInterfaceRequest<Self> {
        return all().filter(sql: sql, arguments: arguments)
    }
    
    /// Creates a request sorted according to the
    /// provided *orderings*.
    ///
    ///     // SELECT * FROM players ORDER BY name
    ///     let request = Player.order(Column("name"))
    ///
    /// The selection defaults to all columns. This default can be changed for
    /// all requests by the `TableRecord.databaseSelection` property, or
    /// for individual requests with the `TableRecord.select` method.
    public static func order(_ orderings: SQLOrderingTerm...) -> QueryInterfaceRequest<Self> {
        return all().order(orderings)
    }
    
    /// Creates a request sorted according to the
    /// provided *orderings*.
    ///
    ///     // SELECT * FROM players ORDER BY name
    ///     let request = Player.order([Column("name")])
    ///
    /// The selection defaults to all columns. This default can be changed for
    /// all requests by the `TableRecord.databaseSelection` property, or
    /// for individual requests with the `TableRecord.select` method.
    public static func order(_ orderings: [SQLOrderingTerm]) -> QueryInterfaceRequest<Self> {
        return all().order(orderings)
    }
    
    /// Creates a request sorted according to *sql*.
    ///
    ///     // SELECT * FROM players ORDER BY name
    ///     let request = Player.order(sql: "name")
    ///
    /// The selection defaults to all columns. This default can be changed for
    /// all requests by the `TableRecord.databaseSelection` property, or
    /// for individual requests with the `TableRecord.select` method.
    public static func order(sql: String, arguments: StatementArguments? = nil) -> QueryInterfaceRequest<Self> {
        return all().order(sql: sql, arguments: arguments)
    }
    
    /// Creates a request which fetches *limit* rows, starting at
    /// *offset*.
    ///
    ///     // SELECT * FROM players LIMIT 1
    ///     let request = Player.limit(1)
    ///
    /// The selection defaults to all columns. This default can be changed for
    /// all requests by the `TableRecord.databaseSelection` property, or
    /// for individual requests with the `TableRecord.select` method.
    public static func limit(_ limit: Int, offset: Int? = nil) -> QueryInterfaceRequest<Self> {
        return all().limit(limit, offset: offset)
    }
    
    /// Creates a request that allows you to define unambiguous expressions
    /// based on the fetched record.
    ///
    /// In the example below, the "team.avgScore < player.score" condition in
    /// the ON clause could be not achieved without table aliases.
    ///
    ///     struct Player: TableRecord {
    ///         static let team = belongsTo(Team.self)
    ///     }
    ///
    ///     // SELECT player.*, team.*
    ///     // JOIN team ON ... AND team.avgScore < player.score
    ///     let playerAlias = TableAlias()
    ///     let request = Player
    ///         .aliased(playerAlias)
    ///         .including(required: Player.team.filter(Column("avgScore") < playerAlias[Column("score")])
    public static func aliased(_ alias: TableAlias) -> QueryInterfaceRequest<Self> {
        return all().aliased(alias)
    }
}
