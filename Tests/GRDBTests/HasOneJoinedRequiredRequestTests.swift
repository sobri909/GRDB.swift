import XCTest
#if GRDBCIPHER
    import GRDBCipher
#elseif GRDBCUSTOMSQLITE
    import GRDBCustomSQLite
#else
    import GRDB
#endif

private typealias Country = AssociationFixture.Country
private typealias CountryProfile = AssociationFixture.CountryProfile

class HasOneJoinedRequiredRequestTests: GRDBTestCase {
    
    func testSimplestRequest() throws {
        let dbQueue = try makeDatabaseQueue()
        try AssociationFixture().migrator.migrate(dbQueue)
        
        try dbQueue.inDatabase { db in
            let graph = try Country
                .joining(required: Country.profile)
                .fetchAll(db)
            
            assertEqualSQL(lastSQLQuery, """
                SELECT "countries".* \
                FROM "countries" \
                JOIN "countryProfiles" ON ("countryProfiles"."countryCode" = "countries"."code")
                """)

            assertMatch(graph, [
                ["code": "FR", "name": "France"],
                ["code": "US", "name": "United States"],
                ["code": "DE", "name": "Germany"],
                ])
        }
    }
    
    func testLeftRequestDerivation() throws {
        let dbQueue = try makeDatabaseQueue()
        try AssociationFixture().migrator.migrate(dbQueue)
        
        try dbQueue.inDatabase { db in
            do {
                // filter before
                let graph = try Country
                    .filter(Column("code") != "FR")
                    .joining(required: Country.profile)
                    .fetchAll(db)
                
                assertEqualSQL(lastSQLQuery, """
                    SELECT "countries".* \
                    FROM "countries" \
                    JOIN "countryProfiles" ON ("countryProfiles"."countryCode" = "countries"."code") \
                    WHERE ("countries"."code" <> 'FR')
                    """)
                
                assertMatch(graph, [
                    ["code": "US", "name": "United States"],
                    ["code": "DE", "name": "Germany"],
                    ])
            }
            
            do {
                // filter after
                let graph = try Country
                    .joining(required: Country.profile)
                    .filter(Column("code") != "FR")
                    .fetchAll(db)
                
                assertEqualSQL(lastSQLQuery, """
                    SELECT "countries".* \
                    FROM "countries" \
                    JOIN "countryProfiles" ON ("countryProfiles"."countryCode" = "countries"."code") \
                    WHERE ("countries"."code" <> 'FR')
                    """)
                
                assertMatch(graph, [
                    ["code": "US", "name": "United States"],
                    ["code": "DE", "name": "Germany"],
                    ])
            }
            
            do {
                // order before
                let graph = try Country
                    .order(Column("code"))
                    .joining(required: Country.profile)
                    .fetchAll(db)
                
                assertEqualSQL(lastSQLQuery, """
                    SELECT "countries".* \
                    FROM "countries" \
                    JOIN "countryProfiles" ON ("countryProfiles"."countryCode" = "countries"."code") \
                    ORDER BY "countries"."code"
                    """)
                
                assertMatch(graph, [
                    ["code": "DE", "name": "Germany"],
                    ["code": "FR", "name": "France"],
                    ["code": "US", "name": "United States"],
                    ])
            }
            
            do {
                // order after
                let graph = try Country
                    .joining(required: Country.profile)
                    .order(Column("code"))
                    .fetchAll(db)
                
                assertEqualSQL(lastSQLQuery, """
                    SELECT "countries".* \
                    FROM "countries" \
                    JOIN "countryProfiles" ON ("countryProfiles"."countryCode" = "countries"."code") \
                    ORDER BY "countries"."code"
                    """)
                
                assertMatch(graph, [
                    ["code": "DE", "name": "Germany"],
                    ["code": "FR", "name": "France"],
                    ["code": "US", "name": "United States"],
                    ])
            }
        }
    }
    
    func testRightRequestDerivation() throws {
        let dbQueue = try makeDatabaseQueue()
        try AssociationFixture().migrator.migrate(dbQueue)
        
        try dbQueue.inDatabase { db in
            do {
                let graph = try Country
                    .joining(required: Country.profile.filter(Column("currency") == "EUR"))
                    .fetchAll(db)
                
                assertEqualSQL(lastSQLQuery, """
                    SELECT "countries".* \
                    FROM "countries" \
                    JOIN "countryProfiles" ON (("countryProfiles"."countryCode" = "countries"."code") AND ("countryProfiles"."currency" = 'EUR'))
                    """)

                // TODO: is it expected/well designed to have countries whose currency is not Euro here?
                // TODO: how to get countries whose currency is Euro?
                assertMatch(graph, [
                    ["code": "FR", "name": "France"],
                    ["code": "DE", "name": "Germany"],
                    ])
            }
            
            do {
                let graph = try Country
                    .joining(required: Country.profile.order(Column("area")))
                    .fetchAll(db)
                
                assertEqualSQL(lastSQLQuery, """
                    SELECT "countries".* \
                    FROM "countries" \
                    JOIN "countryProfiles" ON ("countryProfiles"."countryCode" = "countries"."code")
                    """)
                
                assertMatch(graph, [
                    ["code": "FR", "name": "France"],
                    ["code": "US", "name": "United States"],
                    ["code": "DE", "name": "Germany"],
                    ])
            }
        }
    }
    
    func testRecursion() throws {
        struct Person : TableMapping {
            static let databaseTableName = "persons"
        }
        
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            try db.create(table: "persons") { t in
                t.column("id", .integer).primaryKey()
                t.column("parentId", .integer).references("persons")
            }
        }
        
        try dbQueue.inDatabase { db in
            do {
                let association = Person.hasOne(Person.self)
                let request = Person.joining(required: association)
                try assertEqualSQL(db, request, """
                    SELECT "persons1".* \
                    FROM "persons" "persons1" \
                    JOIN "persons" "persons2" ON ("persons2"."parentId" = "persons1"."id")
                    """)
            }
        }
    }
    
    func testLeftAlias() throws {
        let dbQueue = try makeDatabaseQueue()
        try AssociationFixture().migrator.migrate(dbQueue)
        
        try dbQueue.inDatabase { db in
            do {
                // alias first
                let countryRef = TableReference(alias: "c")
                let request = Country.all()
                    .identified(by: countryRef)
                    .filter(Column("code") != "FR")
                    .joining(required: Country.profile)
                try assertEqualSQL(db, request, """
                    SELECT "c".* \
                    FROM "countries" "c" \
                    JOIN "countryProfiles" ON ("countryProfiles"."countryCode" = "c"."code") \
                    WHERE ("c"."code" <> 'FR')
                    """)
            }
            
            do {
                // alias last
                let countryRef = TableReference(alias: "c")
                let request = Country
                    .filter(Column("code") != "FR")
                    .joining(required: Country.profile)
                    .identified(by: countryRef)
                try assertEqualSQL(db, request, """
                    SELECT "c".* \
                    FROM "countries" "c" \
                    JOIN "countryProfiles" ON ("countryProfiles"."countryCode" = "c"."code") \
                    WHERE ("c"."code" <> 'FR')
                    """)
            }
        }
    }
    
    func testRightAlias() throws {
        let dbQueue = try makeDatabaseQueue()
        try AssociationFixture().migrator.migrate(dbQueue)
        
        try dbQueue.inDatabase { db in
            do {
                // alias first
                let profileRef = TableReference(alias: "a")
                let request = Country.joining(required: Country.profile
                    .identified(by: profileRef)
                    .filter(Column("currency") == "EUR"))
                    .order(Column("area").from("a"))
                try assertEqualSQL(db, request, """
                    SELECT "countries".* \
                    FROM "countries" \
                    JOIN "countryProfiles" "a" ON (("a"."countryCode" = "countries"."code") AND ("a"."currency" = 'EUR')) \
                    ORDER BY "a"."area"
                    """)
            }
            
            do {
                // alias last
                let profileRef = TableReference(alias: "a")
                let request = Country.joining(required: Country.profile
                    .order(Column("area"))
                    .identified(by: profileRef))
                    .filter(Column("currency").from("a") == "EUR")
                try assertEqualSQL(db, request, """
                    SELECT "countries".* \
                    FROM "countries" \
                    JOIN "countryProfiles" "a" ON ("a"."countryCode" = "countries"."code") \
                    WHERE ("a"."currency" = 'EUR')
                    """)
            }
        }
    }
    
    func testLockedAlias() throws {
        let dbQueue = try makeDatabaseQueue()
        try AssociationFixture().migrator.migrate(dbQueue)
        
        try dbQueue.inDatabase { db in
            do {
                // alias left
                let countryRef = TableReference(alias: "COUNTRYPROFILES") // Create name conflict
                let request = Country.joining(required: Country.profile).identified(by: countryRef)
                try assertEqualSQL(db, request, """
                    SELECT "COUNTRYPROFILES".* \
                    FROM "countries" "COUNTRYPROFILES" \
                    JOIN "countryProfiles" "countryProfiles1" ON ("countryProfiles1"."countryCode" = "COUNTRYPROFILES"."code")
                    """)
            }
            
            do {
                // alias right
                let profileRef = TableReference(alias: "COUNTRIES") // Create name conflict
                let request = Country.joining(required: Country.profile.identified(by: profileRef))
                try assertEqualSQL(db, request, """
                    SELECT "countries1".* \
                    FROM "countries" "countries1" \
                    JOIN "countryProfiles" "COUNTRIES" ON ("COUNTRIES"."countryCode" = "countries1"."code")
                    """)
            }
        }
    }
    
    func testConflictingAlias() throws {
        let dbQueue = try makeDatabaseQueue()
        try AssociationFixture().migrator.migrate(dbQueue)
        
        try dbQueue.inDatabase { db in
            do {
                let countryRef = TableReference(alias: "A")
                let profileRef = TableReference(alias: "a")
                let request = Country.joining(required: Country.profile.identified(by: profileRef)).identified(by: countryRef)
                _ = try request.fetchAll(db)
                XCTFail("Expected error")
            } catch let error as DatabaseError {
                XCTAssertEqual(error.resultCode, .SQLITE_ERROR)
                XCTAssertEqual(error.message!, "ambiguous alias: A")
                XCTAssertNil(error.sql)
                XCTAssertEqual(error.description, "SQLite error 1: ambiguous alias: A")
            }
        }
    }
}
