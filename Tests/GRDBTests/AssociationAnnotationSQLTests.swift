import XCTest
// TODO: remove @testable when annotations are ready
#if GRDBCIPHER
    @testable import GRDBCipher
#elseif GRDBCUSTOMSQLITE
    @testable import GRDBCustomSQLite
#else
    @testable import GRDB
#endif

class AssociationAnnotationSQLTests: GRDBTestCase {
    func testVerboseCountAnnotation() throws {
        struct A: TableRecord {
            static let bs = hasMany(B.self)
            static let databaseTableName = "a"
        }
        struct B: TableRecord {
            static let databaseTableName = "b"
        }
        
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            try db.create(table: "a") { t in
                t.column("id").primaryKey()
            }
            try db.create(table: "b") { t in
                t.column("id").primaryKey()
                t.column("aid").references("a")
            }
            
            // That's why we have `A.annotate(with: A.bs.count)`, tested below.
            let bAlias = TableAlias()
            let request = A
                .annotate(with: bAlias[count(Column("id"))])
                .joining(optional: A.bs.aliased(bAlias))
                .group(Column("id"))
            try assertEqualSQL(db, request, """
                SELECT "a".*, COUNT("b"."id") \
                FROM "a" \
                LEFT JOIN "b" \
                ON ("b"."aid" = "a"."id") \
                GROUP BY "a"."id"
                """)
        }
    }
    
    func testCountAnnotation() throws {
        struct A: TableRecord {
            static let bs = hasMany(B.self)
            static let databaseTableName = "a"
        }
        struct B: TableRecord {
            static let databaseTableName = "b"
        }
        
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            try db.create(table: "a") { t in
                t.column("id").primaryKey()
            }
            try db.create(table: "b") { t in
                t.column("id").primaryKey()
                t.column("aid").references("a")
            }
            
            let request = A.annotate(with: A.bs.count)
            try assertEqualSQL(db, request, """
                SELECT "a".*, COUNT("b"."id") \
                FROM "a" \
                LEFT JOIN "b" \
                ON ("b"."aid" = "a"."id") \
                GROUP BY "a"."id"
                """)
        }
    }
    
    func testMultipleCountAnnotation() throws {
        struct A: TableRecord {
            static let namedBs = hasMany(B.filter(Column("name") != nil))
            static let unnamedBs = hasMany(B.filter(Column("name") == nil))
            static let databaseTableName = "a"
        }
        struct B: TableRecord {
            static let databaseTableName = "b"
        }
        
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            try db.create(table: "a") { t in
                t.column("id").primaryKey()
            }
            try db.create(table: "b") { t in
                t.column("id").primaryKey()
                t.column("aid").references("a")
                t.column("name", .text)
            }
            
            let request = A
                .annotate(with: A.namedBs.count)
                .annotate(with: A.unnamedBs.count)
            try assertEqualSQL(db, request, """
                SELECT "a".*, COUNT("b1"."id"), COUNT("b2"."id") \
                FROM "a" \
                LEFT JOIN "b" "b1" ON (("b1"."aid" = "a"."id") AND ("b1"."name" IS NOT NULL)) \
                LEFT JOIN "b" "b2" ON (("b2"."aid" = "a"."id") AND ("b2"."name" IS NULL)) \
                GROUP BY "a"."id"
                """)
        }
    }
}
