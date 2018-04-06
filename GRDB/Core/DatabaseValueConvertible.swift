#if SWIFT_PACKAGE
    import CSQLite
#elseif !GRDBCUSTOMSQLITE && !GRDBCIPHER
    import SQLite3
#endif

// MARK: - DatabaseValueConvertible

/// Types that adopt DatabaseValueConvertible can be initialized from
/// database values.
///
/// The protocol comes with built-in methods that allow to fetch cursors,
/// arrays, or single values:
///
///     try String.fetchCursor(db, "SELECT name FROM ...", arguments:...) // Cursor of String
///     try String.fetchAll(db, "SELECT name FROM ...", arguments:...)    // [String]
///     try String.fetchOne(db, "SELECT name FROM ...", arguments:...)    // String?
///
///     let statement = try db.makeSelectStatement("SELECT name FROM ...")
///     try String.fetchCursor(statement, arguments:...) // Cursor of String
///     try String.fetchAll(statement, arguments:...)    // [String]
///     try String.fetchOne(statement, arguments:...)    // String?
///
/// DatabaseValueConvertible is adopted by Bool, Int, String, etc.
public protocol DatabaseValueConvertible : SQLExpressible {
    /// Returns a value that can be stored in the database.
    var databaseValue: DatabaseValue { get }
    
    /// Returns a value initialized from *dbValue*, if possible.
    static func fromDatabaseValue(_ dbValue: DatabaseValue) -> Self?
    
    /// Returns a value initialized from a missing database column, if possible.
    ///
    /// The default implementation raises a fatal error.
    static func fromMissingDatabaseColumn(_ columnName: String) -> Self
}

extension DatabaseValueConvertible {
    /// [**Experimental**](http://github.com/groue/GRDB.swift#what-are-experimental-features)
    /// :nodoc:
    public var sqlExpression: SQLExpression {
        return databaseValue
    }
    
    /// :nodoc:
    public static func fromMissingDatabaseColumn(_ columnName: String) -> Self {
        // Programmer error
        fatalError("no such column: \(columnName)")
    }
}

/// A cursor of database values extracted from a single column.
/// For example:
///
///     try dbQueue.inDatabase { db in
///         let urls: DatabaseValueCursor<URL> = try URL.fetchCursor(db, "SELECT url FROM links")
///         while let url = urls.next() { // URL
///             print(url)
///         }
///     }
public final class DatabaseValueCursor<Value: DatabaseValueConvertible> : Cursor {
    private let statement: SelectStatement
    private let sqliteStatement: SQLiteStatement
    private let columnIndex: Int32
    private var done = false
    
    init(statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws {
        self.statement = statement
        // We'll read from leftmost column at index 0, unless adapter mangles columns
        self.columnIndex = try Int32(adapter?.baseColumnIndex(atIndex: 0, layout: statement) ?? 0)
        self.sqliteStatement = statement.sqliteStatement
        statement.cursorReset(arguments: arguments)
    }
    
    /// :nodoc:
    public func next() throws -> Value? {
        if done { return nil }
        switch sqlite3_step(sqliteStatement) {
        case SQLITE_DONE:
            done = true
            return nil
        case SQLITE_ROW:
            let dbValue = DatabaseValue(sqliteStatement: sqliteStatement, index: columnIndex)
            return dbValue.losslessConvert() as Value
        case let code:
            statement.database.selectStatementDidFail(statement)
            throw DatabaseError(resultCode: code, message: statement.database.lastErrorMessage, sql: statement.sql, arguments: statement.arguments)
        }
    }
}

/// DatabaseValueConvertible comes with built-in methods that allow to fetch
/// cursors, arrays, or single values:
///
///     try String.fetchCursor(db, "SELECT name FROM ...", arguments:...) // Cursor of String
///     try String.fetchAll(db, "SELECT name FROM ...", arguments:...)    // [String]
///     try String.fetchOne(db, "SELECT name FROM ...", arguments:...)    // String?
///
///     let statement = try db.makeSelectStatement("SELECT name FROM ...")
///     try String.fetchCursor(statement, arguments:...) // Cursor of String
///     try String.fetchAll(statement, arguments:...)    // [String]
///     try String.fetchOne(statement, arguments:...)    // String
///
/// DatabaseValueConvertible is adopted by Bool, Int, String, etc.
extension DatabaseValueConvertible {
    
    // MARK: Fetching From SelectStatement
    
    /// Returns a cursor over values fetched from a prepared statement.
    ///
    ///     let statement = try db.makeSelectStatement("SELECT name FROM ...")
    ///     let names = try String.fetchCursor(statement) // Cursor of String
    ///     while let name = try names.next() { // String
    ///         ...
    ///     }
    ///
    /// If the database is modified during the cursor iteration, the remaining
    /// elements are undefined.
    ///
    /// The cursor must be iterated in a protected dispath queue.
    ///
    /// - parameters:
    ///     - statement: The statement to run.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: A cursor over fetched values.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public static func fetchCursor(_ statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws -> DatabaseValueCursor<Self> {
        return try DatabaseValueCursor(statement: statement, arguments: arguments, adapter: adapter)
    }
    
    /// Returns an array of values fetched from a prepared statement.
    ///
    ///     let statement = try db.makeSelectStatement("SELECT name FROM ...")
    ///     let names = try String.fetchAll(statement)  // [String]
    ///
    /// - parameters:
    ///     - statement: The statement to run.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An array.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public static func fetchAll(_ statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws -> [Self] {
        return try Array(fetchCursor(statement, arguments: arguments, adapter: adapter))
    }
    
    /// Returns a single value fetched from a prepared statement.
    ///
    /// The result is nil if the query returns no row, or if no value can be
    /// extracted from the first row.
    ///
    ///     let statement = try db.makeSelectStatement("SELECT name FROM ...")
    ///     let name = try String.fetchOne(statement)   // String?
    ///
    /// - parameters:
    ///     - statement: The statement to run.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An optional value.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public static func fetchOne(_ statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws -> Self? {
        // fetchOne returns nil if there is no row, or if there is a row with a null value
        let cursor = try DatabaseValueCursor<Self?>(statement: statement, arguments: arguments, adapter: adapter)
        return try cursor.next() ?? nil
    }
}

extension DatabaseValueConvertible {

    // MARK: Fetching From SQL
    
    /// Returns a cursor over values fetched from an SQL query.
    ///
    ///     let names = try String.fetchCursor(db, "SELECT name FROM ...") // Cursor of String
    ///     while let name = try name.next() { // String
    ///         ...
    ///     }
    ///
    /// If the database is modified during the cursor iteration, the remaining
    /// elements are undefined.
    ///
    /// The cursor must be iterated in a protected dispath queue.
    ///
    /// - parameters:
    ///     - db: A database connection.
    ///     - sql: An SQL query.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: A cursor over fetched values.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public static func fetchCursor(_ db: Database, _ sql: String, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws -> DatabaseValueCursor<Self> {
        return try SQLRequest<Self>(sql, arguments: arguments, adapter: adapter).fetchCursor(db)
    }
    
    /// Returns an array of values fetched from an SQL query.
    ///
    ///     let names = try String.fetchAll(db, "SELECT name FROM ...") // [String]
    ///
    /// - parameters:
    ///     - db: A database connection.
    ///     - sql: An SQL query.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An array.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public static func fetchAll(_ db: Database, _ sql: String, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws -> [Self] {
        return try SQLRequest<Self>(sql, arguments: arguments, adapter: adapter).fetchAll(db)
    }
    
    /// Returns a single value fetched from an SQL query.
    ///
    /// The result is nil if the query returns no row, or if no value can be
    /// extracted from the first row.
    ///
    ///     let name = try String.fetchOne(db, "SELECT name FROM ...") // String?
    ///
    /// - parameters:
    ///     - db: A database connection.
    ///     - sql: An SQL query.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An optional value.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public static func fetchOne(_ db: Database, _ sql: String, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws -> Self? {
        return try SQLRequest<Self>(sql, arguments: arguments, adapter: adapter).fetchOne(db)
    }
}

extension FetchRequest where RowDecoder: DatabaseValueConvertible {
    
    // MARK: Fetching Values
    
    /// A cursor over fetched values.
    ///
    ///     let request: ... // Some TypedRequest that fetches String
    ///     let strings = try request.fetchCursor(db) // Cursor of String
    ///     while let string = try strings.next() {   // String
    ///         ...
    ///     }
    ///
    /// If the database is modified during the cursor iteration, the remaining
    /// elements are undefined.
    ///
    /// The cursor must be iterated in a protected dispath queue.
    ///
    /// - parameter db: A database connection.
    /// - returns: A cursor over fetched values.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public func fetchCursor(_ db: Database) throws -> DatabaseValueCursor<RowDecoder> {
        let (statement, adapter) = try prepare(db)
        return try RowDecoder.fetchCursor(statement, adapter: adapter)
    }
    
    /// An array of fetched values.
    ///
    ///     let request: ... // Some TypedRequest that fetches String
    ///     let strings = try request.fetchAll(db) // [String]
    ///
    /// - parameter db: A database connection.
    /// - returns: An array of values.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public func fetchAll(_ db: Database) throws -> [RowDecoder] {
        let (statement, adapter) = try prepare(db)
        return try RowDecoder.fetchAll(statement, adapter: adapter)
    }
    
    /// The first fetched value.
    ///
    /// The result is nil if the request returns no row, or if no value can be
    /// extracted from the first row.
    ///
    ///     let request: ... // Some TypedRequest that fetches String
    ///     let string = try request.fetchOne(db) // String?
    ///
    /// - parameter db: A database connection.
    /// - returns: An optional value.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public func fetchOne(_ db: Database) throws -> RowDecoder? {
        let (statement, adapter) = try prepare(db)
        return try RowDecoder.fetchOne(statement, adapter: adapter)
    }
}
