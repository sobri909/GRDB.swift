// TODO: make public when annotations are ready.
struct Annotation<A: Association> {
    var association: A
    var selectable: (Database) throws -> SQLSelectable
}

extension Association {
    /// TODO
    var count: Annotation<Self> {
        return Annotation(association: self, selectable: { db in
            let primaryKey = try db.primaryKey(RightAssociated.databaseTableName)
            if primaryKey.columns.count == 1 {
                return SQLExpressionCount(Column(primaryKey.columns[0]))
            } else {
                return SQLExpressionCount(Column.rowID)
            }
        })
    }
}

extension QueryInterfaceRequest {
    /// TODO
    func annotate<A>(with annotation: Annotation<A>) -> QueryInterfaceRequest<T>
        where A.LeftAssociated == RowDecoder
    {
        let alias = TableAlias()
        let association = annotation.association.aliased(alias)
        
        return mapQuery { (db, query) in
            let selectable = try alias[annotation.selectable(db)]
            let primaryKey = try db.primaryKey(RowDecoder.databaseTableName)
            return query
                .annotate(with: [selectable])
                .group(primaryKey.columns.map { Column($0) })
        }
        .joining(optional: association)
    }
}

extension TableRecord {
    /// TODO
    static func annotate<A>(with annotation: Annotation<A>) -> QueryInterfaceRequest<Self>
        where A.LeftAssociated == Self
    {
        return all().annotate(with: annotation)
    }
}
