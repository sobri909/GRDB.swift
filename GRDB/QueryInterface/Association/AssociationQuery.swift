struct AssociationQuery {
    var source: SQLSource
    var ownSelection: [SQLSelectable]
    var includedSelection: [SQLSelectable]
    var onExpression: SQLExpression?
    var ordering: QueryOrdering
    var rowAdapter: RowAdapter?
    
    // Input: SELECT * FROM foo ORDER BY bar
    // Output: SELECT foo.* FROM foo ORDER BY foo.bar
    func qualified(with qualifier: inout SQLTableQualifier) -> AssociationQuery {
        let qualifiedSource = source.qualified(with: &qualifier)
        return AssociationQuery(
            source: qualifiedSource,
            ownSelection: ownSelection.map { $0.qualifiedSelectable(with: qualifier) },
            includedSelection: includedSelection.map { $0.qualifiedSelectable(with: qualifier) },
            onExpression: onExpression?.qualifiedExpression(with: qualifier),
            ordering: ordering.qualified(with: qualifier),
            rowAdapter: rowAdapter)
    }
}

extension AssociationQuery {
    init(_ query: QueryInterfaceQuery) {
        GRDBPrecondition(!query.isDistinct, "Not implemented: join distinct queries")
        GRDBPrecondition(query.rowAdapter == nil, "Not implemented: defining associations from joined requests")
        GRDBPrecondition(query.groupByExpressions.isEmpty, "Can't join aggregated queries")
        GRDBPrecondition(query.havingExpression == nil, "Can't join aggregated queries")
        GRDBPrecondition(query.limit == nil, "Can't join limited queries")
        
        self.init(
            source: query.source,
            ownSelection: query.selection,
            includedSelection: [],
            onExpression: query.whereExpression,
            ordering: query.ordering,
            rowAdapter: nil)
    }
}

extension AssociationQuery {
    func select(_ selection: [SQLSelectable]) -> AssociationQuery {
        assert(rowAdapter == nil, """
            can't change selection after rowAdapter has been defined since \
            rowAdapter relies on column offsets \
            (see the joining(...) method below)
            """)
        // TODO: preserve qualifier
        var query = self
        query.ownSelection = selection
        return query
    }
    
    func annotate(with selection: [SQLSelectable]) -> AssociationQuery {
        assert(rowAdapter == nil, """
            can't change selection after rowAdapter has been defined since \
            rowAdapter relies on column offsets \
            (see the joining(...) method below)
            """)
        // TODO: preserve qualifier
        var query = self
        query.ownSelection += selection
        return query
    }
    
    func filter(_ predicate: SQLExpressible) -> AssociationQuery {
        // TODO: preserve qualifier
        var query = self
        if let expression = query.onExpression {
            query.onExpression = expression && predicate.sqlExpression
        } else {
            query.onExpression = predicate.sqlExpression
        }
        return query
    }
    
    func none() -> AssociationQuery {
        var query = self
        query.onExpression = false.sqlExpression
        return query
    }
    
    func order(_ orderings: [SQLOrderingTerm]) -> AssociationQuery {
        return order(QueryOrdering(orderings: orderings))
    }
    
    func reversed() -> AssociationQuery {
        return order(ordering.reversed())
    }
    
    private func order(_ ordering: QueryOrdering) -> AssociationQuery {
        assert(rowAdapter == nil, """
            can't change ordering after rowAdapter has been defined since \
            ordering have been consumed when rowAdapter is defined \
            (see the joining(...) method below)
            """)
        
        // Apply qualifier if present
        let newOrdering: QueryOrdering
        if let qualifier = source.qualifier {
            newOrdering = ordering.qualified(with: qualifier)
        } else {
            newOrdering = ordering
        }
        
        var query = self
        query.ordering = newOrdering
        return query
    }
}

extension AssociationQuery {
    func chaining(
        db: Database,
        chainOp: AssociationChainOperator,
        rightQuery: AssociationQuery,
        rightKey: String,
        mapping: AssociationMapping)
        throws -> AssociationQuery
    {
        var leftQualifier = SQLTableQualifier()
        var rightQualifier = SQLTableQualifier()
        
        let leftQualifiedQuery = qualified(with: &leftQualifier)
        let rightQualifiedQuery = rightQuery.qualified(with: &rightQualifier)
        
        let leftQualifiedOwnSelection = leftQualifiedQuery.ownSelection
        let leftQualifiedIncludedSelection = leftQualifiedQuery.includedSelection
        let rightQualifiedOwnSelection = rightQualifiedQuery.ownSelection
        let rightQualifiedIncludedSelection = rightQualifiedQuery.includedSelection
        let rightQualifiedSelection = rightQualifiedOwnSelection + rightQualifiedIncludedSelection
        
        let chainedOwnSelection = leftQualifiedOwnSelection
        let chainedIncludedSelection = leftQualifiedIncludedSelection + rightQualifiedSelection
        
        let leftOwnSelectionWidth = try leftQualifiedOwnSelection
            .map { try $0.columnCount(db) }
            .reduce(0, +)
        
        let leftAdapter = leftQualifiedQuery.rowAdapter ?? RangeRowAdapter(0..<leftOwnSelectionWidth)
        let chainedAdapter: RowAdapter
        if rightQualifiedSelection.isEmpty {
            chainedAdapter = leftAdapter
        } else {
            // Compute offset for rightAdapter
            // So far, Only AssociationRowScopeSearchTests.testScopeSearchIsBreadthFirst
            // tests that the scope for d is valid in `a.include(b.include(c).include(d))`
            // (parallel joins behind a first join).
            let leftIncludedSelectionWidth = try leftQualifiedIncludedSelection
                .map { try $0.columnCount(db) }
                .reduce(0, +)
            let leftSelectionWidth = leftOwnSelectionWidth + leftIncludedSelectionWidth
            
            if let rightAdapter = rightQualifiedQuery.rowAdapter {
                let rightAdapter = OffsettedAdapter(rightAdapter, offset: leftSelectionWidth)
                chainedAdapter = leftAdapter.addingScopes([rightKey: rightAdapter])
            } else {
                let rightOwnSelectionWidth = try rightQualifiedOwnSelection
                    .map { try $0.columnCount(db) }
                    .reduce(0, +)
                let rightAdapter = RangeRowAdapter(leftSelectionWidth ..< leftSelectionWidth + rightOwnSelectionWidth)
                chainedAdapter = leftAdapter.addingScopes([rightKey: rightAdapter])
            }
        }
        
        let chainedSource = leftQualifiedQuery.source.chaining(
            db: db,
            chainOp: chainOp,
            on: mapping,
            and: rightQualifiedQuery.onExpression,
            to: rightQualifiedQuery.source)
        
        let chainedOrdering = leftQualifiedQuery.ordering.appending(rightQualifiedQuery.ordering)
        
        return AssociationQuery(
            source: chainedSource,
            ownSelection: chainedOwnSelection,
            includedSelection: chainedIncludedSelection,
            onExpression: leftQualifiedQuery.onExpression,
            ordering: chainedOrdering,
            rowAdapter: chainedAdapter)
    }
}
