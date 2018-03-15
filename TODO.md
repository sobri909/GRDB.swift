- [ ] Attach databases. Interesting question: what happens when one attaches a non-WAL db to a databasePool?
- [ ] SQLCipher: sqlite3_rekey is discouraged (https://github.com/ccgus/fmdb/issues/547#issuecomment-259219320)
- [ ] Query builder
    - [ ] SELECT readers.*, books.* FROM ... JOIN ...
    - [ ] date functions
    - [ ] NOW/CURRENT_TIMESTAMP
    - [ ] ROUND() http://marc.info/?l=sqlite-users&m=130419182719263
    - [ ] RANDOM() https://www.sqlite.org/lang_corefunc.html
    - [ ] GLOB https://www.sqlite.org/lang_expr.html
    - [ ] REGEXP https://www.sqlite.org/lang_expr.html
    - [ ] CASE x WHEN w1 THEN r1 WHEN w2 THEN r2 ELSE r3 END https://www.sqlite.org/lang_expr.html
- [ ] Write regression tests for #156 and #157
- [ ] Allow concurrent reads from a snapshot
- [ ] Decode NSDecimalNumber from text database values

Xcode 9.3, Swift 4.1

- [ ] Audit Cursor return types and make it look as much as possible as stdlib's lazy sequence

GRDB 3.0

- [ ] Refactor SQL generation and rowId extraction from expression on the visitor pattern. Provide more documentation for literal expressions which become the only way to extend GRDB. Remove QueryInterfaceExtensibilityTests.swift
- [ ] Make DatabasePool.write safe. See https://github.com/groue/GRDB.swift/commit/5e3c7d9c430df606a1cccfd4983be6b50e778a5c#commitcomment-26988970
- [ ] Do one of those two:
    1. Make save() impossible to customize: remove it from MutablePersistableRecord protocol, and remove performSave() from tne public API.
    2. Open Record.save()
- [ ] Not sure: Make the MutableEncodableRecord.update(_:columns:) method mutating (as support for an updatedDate column). If so, allow type to change the set of changed columns.
- [ ] Not sure: type safety
    - [ ] Introduce some record protocol with an associated primary key type. Restrict filter(key:) methods to this type. Allow distinguishing FooId from BarId types.
    - [ ] Replace Column with TypedColumn. How to avoid code duplication (repeated types)? Keypaths?
- [ ] Not sure: Consider introducing RowDecodable and RowEncodable on top of FetchableRecord and MutableEncodableRecordRecord. This would allow keeping fetching and persistence methods private in some files.
- [ ] Rename columnCount -> numberOfColumns
- [ ] Try to remove double EncodableRecord/MutableEncodableRecord protocols: Would non-mutating Record methods help?
- [ ] Association Mammoth: One terrible request with parallel joins, chained joins, name conflict, filtering, ordering, annotation, conditions on several distinct tables
- [ ] Replace `t.column("id", .integer).primaryKey()` with `t.autoIncrementedPrimaryKey("id")` in the documentation.
- [ ] Enhance database regions for counted and joined requests (when we don't care about updates, but only about insertions and deletions)
- [ ] Doc: replace book->author with passport->country?
- [ ] Doc: replace all plural database table names with singular
- [ ] https://github.com/groue/GRDB.swift/pull/319#issuecomment-373366408
- [ ] HELP NEEDED: criticize singular table name convention, only due to defaultAssociationKey(for:).

- [ ] DatabaseMigrator exposes the name of its support table (useful for tests that check which application tables are present). Alternative: have GRDB tell if a database table name is reserved by GRDB.
- [ ] Ask DatabaseMigrator if a migration has been applied (useful for tests that check if a legacy database resource should be tested or not)
- [ ] DatabaseMigrator.isInternalTable
- [ ] DatabaseMigrator.canMigrate(_:upTo:)
- [ ] Database.isSQLiteInternalTable
- [ ] HiddenColumnsAdapter

- [ ] NON-BLOCKING: Full text join (content-less ft table)
- [ ] NON-BLOCKING: free associations
    - [ ] Make public FreeAssociation and related APIs
    - [ ] Fix and make public QueryInterfaceRequest.including(optional:QueryInterfaceRequest) et al.
    - [ ] Fix and make public TableRecord.including(optional:QueryInterfaceRequest) et al.
    - [ ] Remove @testable frrom AssociationFreeSQLTests.swift
- [ ] NON-BLOCKING: Enhance database regions for joined requests (rowids) (see DatabaseRegionTests.testDatabaseRegionOfJoinedRequests)
- [ ] HELP NEEDED, NON-BLOCKING: annotations
    - [ ] How to consume annotations?
    - [ ] Make public Annotation.swift and related APIs
    - [ ] Remove @testable from AssociationAnnotationSQLTests.swift
- [ ] HELP NEEDED, NON-BLOCKING: complex chains
    
    A chain is "complex" when:
    - A key is redefined, as in Foo.including(Foo.bar).including(Foo.bar)
    - An optional chain is followed by a required chain, as in Foo.including(optional: Foo.bar).including(required: Bar.baz)
    
    Those two problems happen because one can use queries that are already joined:
    
    - Case 1:
        
        let base = Foo.makeRequest() // returns Foo.including(Foo.bar)
        let request = base.including(Foo.bar) // unconscious redefinition of "bar"
    
    - Case 2:
        
        let assoc = Foo.specialBar // returns Foo.belongsTo(Foo.bar.including(required: Bar.baz))
        let request = Foo.including(optional: assoc) // optional followed by required
    
    - [ ] hasOne/ManyThrough
    - [ ] Solve the "optional followed by required"" problem (look for TODO: chainOptionalRequired)
    - [ ] Decide if redefinition (Foo.including(Foo.bar).including(Foo.bar)) should:
        - *Fatal error* because we redefine the query for the key "bar" ?
        - *Intersect* the queries named "bar"?
            - Foo.include(required: Foo.bar).include(optional: Foo.bar) <=> Foo.include(required: Foo.bar)
            - Foo.include(required: Foo.bar.filter(f1)).include(optional: Foo.bar.filter(f2)) <=> Foo.include(required: Foo.bar.filter(f1 && f2)


Not sure

- [ ] encode/decode nested records/arrays/dictionaries as JSON?
- [ ] Think about supporting Cursor's underestimatedCount, which could speed up Array(cursor) and fetchAll()
- [ ] Support for OR ROLLBACK, and mismatch between the Swift depth and the SQLite depth of nested transactions/savepoint:
    
    ```swift
    try db.inTransaction {           // Swift depth: 1, SQLite depth: 1
        try db.execute("COMMIT")     // Swift depth: 1, SQLite depth: 0
        try db.execute("INSERT ...") // Should throw an error since this statement is no longer protected by a transaction
        try db.execute("SELECT ...") // Should throw an error since this statement is no longer protected by a transaction
        return .commit 
    }
    ```

    ```swift
    try db.inTransaction {
        try db.execute("INSERT OR ROLLBACK ...") // throws 
        return .commit // not executed because of error
    }   // Should not ROLLBACK since transaction has already been rollbacked
    ```

    ```swift
    try db.inTransaction {
        do {
            try db.execute("INSERT OR ROLLBACK ...") // throws
        } catch {
        }
        try db.execute("INSERT ...") // Should throw an error since this statement is no longer protected by a transaction
        try db.execute("SELECT ...") // Should throw an error since this statement is no longer protected by a transaction
        return .commit
    }
    ```

    ```swift
    try db.inTransaction {
        do {
            try db.execute("INSERT OR ROLLBACK ...") // throws
        } catch {
        }
        return .commit  // Should throw an error since transaction has been rollbacked and user's intent can not be applied
    }
    ```


Requires recompilation of SQLite:

- [ ] https://www.sqlite.org/c3ref/column_database_name.html could help extracting out of a row a subrow only made of columns that come from a specific table. Requires SQLITE_ENABLE_COLUMN_METADATA which is not set on the sqlite3 lib that ships with OSX.



Reading list:

- VACUUM (https://blogs.gnome.org/jnelson/)
- http://www.sqlite.org/intern-v-extern-blob.html
- https://sqlite.org/sharedcache.html
- Undo: https://www.sqlite.org/undoredo.html
- Undo: https://sqlite.org/sessionintro.html
- Swift, Xcode:List of Swift documentation keywords: https://swift.org/documentation/api-design-guidelines.html#special-instructions
- Swift, Xcode:Amazing tip from Xcode labs: add a EXCLUDED_SOURCE_FILE_NAMES build setting to conditionally exclude sources for different configuration: https://twitter.com/zats/status/74386298602026496
- SQLITE_ENABLE_SQLLOG: http://mjtsai.com/blog/2016/07/19/sqlite_enable_sqllog/
- Swift, Xcode: https://github.com/apple/swift/blob/master/docs/OptimizationTips.rst
- Associations: http://docs.diesel.rs/diesel/associations/index.html
- FTS: http://cocoamine.net/blog/2015/09/07/contentless-fts4-for-large-immutable-documents/
- pinyin: http://hustlzp.com/post/2016/02/ios-full-text-search-using-sqlite-fts4
- FetchedRecordsController: https://github.com/jflinter/Dwifft
- FetchedRecordsController: https://github.com/wokalski/Diff.swift (Faster)
- FetchedRecordsController: https://github.com/andre-alves/PHDiff
- React oddity: http://stackoverflow.com/questions/41721769/realm-update-object-without-updating-lists
- File protection: https://github.com/ccgus/fmdb/issues/262
- File protection: https://lists.apple.com/archives/cocoa-dev/2012/Aug/msg00527.html
- [iOS apps are terminated every time they enter the background if they share an encrypted database with an app extension](https://github.com/sqlcipher/sqlcipher/issues/255)
