import XCTest
// TODO: remove @testable when free association is ready.
#if GRDBCIPHER
    @testable import GRDBCipher
#elseif GRDBCUSTOMSQLITE
    @testable import GRDBCustomSQLite
#else
    @testable import GRDB
#endif

private struct A: TableRecord {
    static let databaseTableName = "a"
}

private struct B: TableRecord {
    static let databaseTableName = "b"
}

/// Test SQL generation
class AssociationFreeSQLTests: GRDBTestCase {
    
    override func setup(_ dbWriter: DatabaseWriter) throws {
        try dbWriter.write { db in
            try db.create(table: "a") { t in
                t.column("id", .integer)
                t.column("foo", .text)
            }
            try db.create(table: "b") { t in
                t.column("id", .integer)
                t.column("bar", .text)
            }
        }
    }
    
    func testFreeAssociationToRecord() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let association = A.associationTo(B.self)
            let request = A.including(required: association)
            try assertEqualSQL(db, request, """
                SELECT "a".*, "b".* \
                FROM "a" \
                JOIN "b"
                """)
        }
    }
    
    func testFreeAssociationToRecordWithMapping() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let association = A.associationTo(B.self) { (a, b) in a[Column("foo")] == b[Column("bar")] }
            let request = A.including(required: association)
            try assertEqualSQL(db, request, """
                SELECT "a".*, "b".* \
                FROM "a" \
                JOIN "b" ON ("a"."foo" = "b"."bar")
                """)
        }
    }
    
    func testFreeAssociationToRequest() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let bRequest = B.filter(Column("bar") != nil)
            let association = A.associationTo(bRequest)
            let request = A.including(required: association)
            try assertEqualSQL(db, request, """
                SELECT "a".*, "b".* \
                FROM "a" \
                JOIN "b" ON ("b"."bar" IS NOT NULL)
                """)
        }
    }
    
    func testFreeAssociationToRequestWithMapping() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let bRequest = B.filter(Column("bar") != nil)
            let association = A.associationTo(bRequest) { (a, b) in a[Column("foo")] == b[Column("bar")] }
            let request = A.including(required: association)
            try assertEqualSQL(db, request, """
                SELECT "a".*, "b".* \
                FROM "a" \
                JOIN "b" ON (("a"."foo" = "b"."bar") AND ("b"."bar" IS NOT NULL))
                """)
        }
    }
    
    func testFreeAssociationFilter() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let association = A
                .associationTo(B.self) { (a, b) in a[Column("foo")] == b[Column("bar")] }
                .filter(Column("bar") != nil)
            let request = A.including(required: association)
            try assertEqualSQL(db, request, """
                SELECT "a".*, "b".* \
                FROM "a" \
                JOIN "b" ON (("a"."foo" = "b"."bar") AND ("b"."bar" IS NOT NULL))
                """)
        }
    }
    
    func testFreeJoinToRequest() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            do {
                let bRequest = B.filter(Column("bar") != nil)
                let request = A.including(required: bRequest)
                try assertEqualSQL(db, request, """
                    SELECT "a".*, "b".* \
                    FROM "a" \
                    JOIN "b" ON ("b"."bar" IS NOT NULL)
                    """)
            }
            do {
                let bRequest = B.filter(Column("bar") != nil)
                let request = A.including(optional: bRequest)
                try assertEqualSQL(db, request, """
                    SELECT "a".*, "b".* \
                    FROM "a" \
                    LEFT JOIN "b" ON ("b"."bar" IS NOT NULL)
                    """)
            }
            do {
                let bRequest = B.filter(Column("bar") != nil)
                let request = A.joining(required: bRequest)
                try assertEqualSQL(db, request, """
                    SELECT "a".* \
                    FROM "a" \
                    JOIN "b" ON ("b"."bar" IS NOT NULL)
                    """)
            }
            do {
                let bRequest = B.filter(Column("bar") != nil)
                let request = A.joining(optional: bRequest)
                try assertEqualSQL(db, request, """
                    SELECT "a".* \
                    FROM "a" \
                    LEFT JOIN "b" ON ("b"."bar" IS NOT NULL)
                    """)
            }
        }
    }
}
