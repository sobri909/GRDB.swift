extension QueryInterfaceRequest where RowDecoder: TableRecord {
    func chain<A: Association>(_ chainOp: AssociationChainOperator, _ association: A)
        -> QueryInterfaceRequest<RowDecoder>
        where A.LeftAssociated == RowDecoder
    {
        return mapQueryChain { (db, leftQuery) in
            // FIXME: if joinOp is left, then association.request.query should only use left joins,
            // and turn the inner joins into (primary key is not null) requirements
            let rightQuery = try association.request.query(db)
            return try leftQuery.chaining(
                db: db,
                chainOp: chainOp,
                rightQuery: rightQuery,
                rightKey: association.key,
                mapping: association.associationMapping(db))
        }
    }
    
    // MARK: - Associations
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are selected. The returned association does not
    /// require that the associated database table contains a matching row.
    public func including<A: Association>(optional association: A)
        -> QueryInterfaceRequest<RowDecoder>
        where A.LeftAssociated == RowDecoder
    {
        return chain(.optional, association)
    }
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are selected. The returned association requires
    /// that the associated database table contains a matching row.
    public func including<A: Association>(required association: A)
        -> QueryInterfaceRequest<RowDecoder>
        where A.LeftAssociated == RowDecoder
    {
        return chain(.required, association)
    }
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are not selected. The returned association does not
    /// require that the associated database table contains a matching row.
    public func joining<A: Association>(optional association: A)
        -> QueryInterfaceRequest<RowDecoder>
        where A.LeftAssociated == RowDecoder
    {
        return chain(.optional, association.select([]))
    }
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are not selected. The returned association requires
    /// that the associated database table contains a matching row.
    public func joining<A: Association>(required association: A)
        -> QueryInterfaceRequest<RowDecoder>
        where A.LeftAssociated == RowDecoder
    {
        return chain(.required, association.select([]))
    }
    
    // MARK: - Free Associations
    
    // TODO: those methods are error prone. Make them public when they are
    // fixed.
    //
    // It's easy and surely correct to write Parent.include(Parent.child)
    // But it's easy and not obviously correct to write Parent.include(Child.all())
    //
    // The last example builds a "free" association which does not use the foreign key.
    // It's not obvious, when reading Parent.include(Child.all()), that the foreign key
    // is not used.
    //
    // We need to fix the API, so that it is clear when joins are "free".
    //
    // The same problem applies to Parent.associationTo(Child.all()).
    //
    // Possible fixes:
    //
    // let assoc = Parent.detachedAssociationTo(Child.all())
    // let results = Parent.include(assoc)
    // let results = Parent.includeDetached(optional: Child.all())
    /// TODO
    func including<Right>(optional request: QueryInterfaceRequest<Right>)
        -> QueryInterfaceRequest<RowDecoder>
        where Right: TableRecord
    {
        return chain(.optional, RowDecoder.associationTo(request))
    }
    
    /// TODO
    func including<Right>(required request: QueryInterfaceRequest<Right>)
        -> QueryInterfaceRequest<RowDecoder>
        where Right: TableRecord
    {
        return chain(.required, RowDecoder.associationTo(request))
    }
    
    /// TODO
    func joining<Right>(optional request: QueryInterfaceRequest<Right>)
        -> QueryInterfaceRequest<RowDecoder>
        where Right: TableRecord
    {
        return chain(.optional, RowDecoder.associationTo(request.select([])))
    }
    
    /// TODO
    func joining<Right>(required request: QueryInterfaceRequest<Right>)
        -> QueryInterfaceRequest<RowDecoder>
        where Right: TableRecord
    {
        return chain(.required, RowDecoder.associationTo(request.select([])))
    }
}

extension Association where LeftAssociated: MutablePersistableRecord {
    // Base for Parent.children.request(from: parent) which returns a request
    // for children linked to a parent.
    func request(from record: LeftAssociated) -> QueryInterfaceRequest<RightAssociated> {
        // Implementation is super fragile.
        //
        // So far, it is only supported by tests, which may miss non-trivial
        // cases that will break apart.
        return QueryInterfaceRequest(queryPromise: { db in
            // Resolve association query
            let rightQuery = try self.request.query(db)
            
            // Look up mapping from origin record to associated records.
            let associationMapping = try self.associationMapping(db)
            
            // Mapping needs table references
            // (weird: the left one is qualified with a table name, but not the right one)
            // (weird: qualifiers are not disambiguated)
            let leftQualifier = SQLTableQualifier()
            leftQualifier.tableName = LeftAssociated.databaseTableName
            let leftAlias = TableAlias(qualifier: leftQualifier)
            let rightAlias = TableAlias()
            
            let resolvedQuery: AssociationQuery
            if let filter = associationMapping(leftAlias, rightAlias)?.sqlExpression {
                // Resolve filter with record's persistence container
                // This turns (foo.id = bar.id) into (foo.id = 1).
                let leftContainer = PersistenceContainer(record)
                let resolutionContext = [leftAlias.qualifier.qualifiedName!: leftContainer]
                let resolvedFilter = filter.resolvedExpression(inContext: resolutionContext)
                resolvedQuery = rightQuery.filter(resolvedFilter)
            } else {
                resolvedQuery = rightQuery
            }
            
            GRDBPrecondition(resolvedQuery.includedSelection.isEmpty, "Not implemented: requesting joined requests")
            GRDBPrecondition(resolvedQuery.rowAdapter == nil, "Not implemented: requesting adapted requests")
            
            return QueryInterfaceQuery(
                source: resolvedQuery.source,
                selection: resolvedQuery.ownSelection,
                whereExpression: resolvedQuery.onExpression)
        })
    }
}

extension MutablePersistableRecord {
    /// Creates a request that fetches the associated record(s).
    ///
    /// For example:
    ///
    ///     struct Player: TableRecord {
    ///         static let team = belongsTo(Team.self)
    ///     }
    ///
    ///     let player: Player = ...
    ///     let request = player.request(Player.team)
    ///     let team = try request.fetchOne(db) // Team?
    public func request<A: Association>(_ association: A)
        -> QueryInterfaceRequest<A.RightAssociated>
        where A.LeftAssociated == Self
    {
        return association.request(from: self)
    }
    
    // TODO: test
    /// Fetches a cursor of associated records.
    ///
    /// For example:
    ///
    ///     struct Player: TableRecord {
    ///         static let rounds = hasMany(Round.self)
    ///     }
    ///
    ///     let player: Player = ...
    ///     let rounds = try player.fetchCursor(db, Player.rounds) // Cursor of Round
    public func fetchCursor<A: Association>(_ db: Database,_ association: A)
        throws -> RecordCursor<A.RightAssociated>
        where A.LeftAssociated == Self, A.RightAssociated: FetchableRecord
    {
        return try request(association).fetchCursor(db)
    }
    
    // TODO: test
    /// Fetches an array of associated records.
    ///
    /// For example:
    ///
    ///     struct Player: TableRecord {
    ///         static let rounds = hasMany(Round.self)
    ///     }
    ///
    ///     let player: Player = ...
    ///     let rounds = try player.fetchAll(db, Player.rounds) // [Round]
    public func fetchAll<A: Association>(_ db: Database,_ association: A)
        throws -> [A.RightAssociated]
        where A.LeftAssociated == Self, A.RightAssociated: FetchableRecord
    {
        return try request(association).fetchAll(db)
    }
    
    // TODO: test
    /// Fetches an associated record.
    ///
    /// For example:
    ///
    ///     struct Player: TableRecord {
    ///         static let team = belongsTo(Team.self)
    ///     }
    ///
    ///     let player: Player = ...
    ///     let team = try player.fetchOne(db, Player.team) // Team?
    public func fetchOne<A: Association>(_ db: Database,_ association: A)
        throws -> A.RightAssociated?
        where A.LeftAssociated == Self, A.RightAssociated: FetchableRecord
    {
        return try request(association).fetchOne(db)
    }
}

extension TableRecord {
    
    // MARK: - Associations
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are selected. The returned association does not
    /// require that the associated database table contains a matching row.
    public static func including<A: Association>(optional association: A)
        -> QueryInterfaceRequest<Self>
        where A.LeftAssociated == Self
    {
        return all().including(optional: association)
    }
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are selected. The returned association requires
    /// that the associated database table contains a matching row.
    public static func including<A: Association>(required association: A)
        -> QueryInterfaceRequest<Self>
        where A.LeftAssociated == Self
    {
        return all().including(required: association)
    }
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are not selected. The returned association does not
    /// require that the associated database table contains a matching row.
    public static func joining<A: Association>(optional association: A)
        -> QueryInterfaceRequest<Self>
        where A.LeftAssociated == Self
    {
        return all().joining(optional: association)
    }
    
    /// Creates a request that includes an association. The columns of the
    /// associated record are not selected. The returned association requires
    /// that the associated database table contains a matching row.
    public static func joining<A: Association>(required association: A)
        -> QueryInterfaceRequest<Self>
        where A.LeftAssociated == Self
    {
        return all().joining(required: association)
    }
    
    // MARK: - Free Associations
    
    // TODO: those methods are error prone. Make them public when they are
    // fixed.
    /// TODO
    static func including<Right>(optional request: QueryInterfaceRequest<Right>)
        -> QueryInterfaceRequest<Self>
        where Right: TableRecord
    {
        return all().including(optional: request)
    }
    
    /// TODO
    static func including<Right>(required request: QueryInterfaceRequest<Right>)
        -> QueryInterfaceRequest<Self>
        where Right: TableRecord
    {
        return all().including(required: request)
    }
    
    /// TODO
    static func joining<Right>(optional request: QueryInterfaceRequest<Right>)
        -> QueryInterfaceRequest<Self>
        where Right: TableRecord
    {
        return all().joining(optional: request)
    }
    
    /// TODO
    static func joining<Right>(required request: QueryInterfaceRequest<Right>)
        -> QueryInterfaceRequest<Self>
        where Right: TableRecord
    {
        return all().joining(required: request)
    }
}
