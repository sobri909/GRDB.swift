/// A column in the database
///
/// See https://github.com/groue/GRDB.swift#the-query-interface
public struct Column : SQLExpression {
    /// The hidden rowID column
    public static let rowID = Column("rowid")
    
    /// The name of the column
    public let name: String
    
    private var qualifier: SQLTableQualifier?
    
    /// Creates a column given its name.
    public init(_ name: String) {
        self.name = name
    }
    
    /// [**Experimental**](http://github.com/groue/GRDB.swift#what-are-experimental-features)
    /// :nodoc:
    public func expressionSQL(_ arguments: inout StatementArguments?) -> String {
        if let qualifierName = qualifier?.qualifiedName {
            return qualifierName.quotedDatabaseIdentifier + "." + name.quotedDatabaseIdentifier
        }
        return name.quotedDatabaseIdentifier
    }
    
    /// [**Experimental**](http://github.com/groue/GRDB.swift#what-are-experimental-features)
    /// :nodoc:
    public func qualifiedExpression(with qualifier: SQLTableQualifier) -> SQLExpression {
        if self.qualifier != nil {
            // Never requalify
            return self
        }
        var column = self
        column.qualifier = qualifier
        return column
    }
    
    /// [**Experimental**](http://github.com/groue/GRDB.swift#what-are-experimental-features)
    /// :nodoc:
    public func resolvedExpression(inContext context: [String: PersistenceContainer]) -> SQLExpression {
        guard
            let qualifier = qualifier,
            let qualifiedName = qualifier.qualifiedName,
            let container = context[qualifiedName],
            let value = container.value(forCaseInsensitiveColumn: name) else
        {
            return self
        }
        
        return value
    }
}
