/// In `SELECT a.*, b.* FROM a JOIN b ON b.aid = a.id AND b.name = 'foo'`,
/// the AssociationRequest is (`b.*` + `b.name = 'foo'`).
public struct AssociationRequest<T> {
    // A QueryInterfaceRequest can turn into an AssociationQuery once given
    // a database connection.
    private var queryPromise: DatabasePromise<AssociationQuery>
    
    // Processing of the query filters, orderings, selection...
    private var transforms: [DatabaseTransform<AssociationQuery>] = []
    
    // Processing of the query chains. Must happen after selection has been
    // defined, so that the selected rows have a fixed layout on which we can
    // define row scopes that help consuming joined rows.
    private var chainTransforms: [DatabaseTransform<AssociationQuery>] = []
    
    init(queryPromise: @escaping DatabasePromise<AssociationQuery>) {
        self.queryPromise = queryPromise
    }
    
    init(query: AssociationQuery) {
        self.init(queryPromise: { _ in query })
    }
    
    func query(_ db: Database) throws -> AssociationQuery {
        var query = try queryPromise(db)
        
        // Filters, orderings, selection...
        query = try transforms.reduce(query) { try $1(db, $0) }
        
        // Query chains
        query = try chainTransforms.reduce(query) { try $1(db, $0) }
        
        return query
    }
    
    func mapQuery(_ transform: @escaping DatabaseTransform<AssociationQuery>) -> AssociationRequest<T> {
        var request = self
        request.transforms.append(transform)
        return request
    }
    
    func mapQueryChain(_ transform: @escaping DatabaseTransform<AssociationQuery>) -> AssociationRequest<T> {
        var request = self
        request.chainTransforms.append(transform)
        return request
    }
}

extension AssociationRequest {
    init(_ request: QueryInterfaceRequest<T>) {
        self.init(queryPromise: { db in try AssociationQuery(request.query(db)) })
    }
}

extension AssociationRequest where T: TableRecord {
    
    /// Creates a request with the provided primary key *predicate*.
    func filter<PrimaryKeyType: DatabaseValueConvertible>(key: PrimaryKeyType?) -> AssociationRequest<T> {
        guard let key = key else {
            return AssociationRequest(T.none())
        }
        
        return filter(keys: [key])
    }

    /// Creates a request with the provided primary key *predicate*.
    func filter<Sequence: Swift.Sequence>(keys: Sequence) -> AssociationRequest<T> where Sequence.Element: DatabaseValueConvertible {
        let keys = Array(keys)
        let makePredicate: (Column) -> SQLExpression
        switch keys.count {
        case 0:
            return AssociationRequest(T.none())
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
    /// When executed, this request raises a fatal error if there is no unique
    /// index on the key columns.
    func filter(key: [String: DatabaseValueConvertible?]?) -> AssociationRequest<T> {
        guard let key = key else {
            return AssociationRequest(T.none())
        }
        
        return filter(keys: [key])
    }
    
    /// Creates a request with the provided primary key *predicate*.
    ///
    /// When executed, this request raises a fatal error if there is no unique
    /// index on the key columns.
    func filter(keys: [[String: DatabaseValueConvertible?]]) -> AssociationRequest<T> {
        guard !keys.isEmpty else {
            return AssociationRequest(T.none())
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
