GRDB Associations
=================

> [**:fire: EXPERIMENTAL**](http://github.com/groue/GRDB.swift#what-are-experimental-features): GRDB associations are young, and not stabilized yet. To help them becoming stable, [your feedback](https://github.com/groue/GRDB.swift/issues) is greatly appreciated.


## Chapters

- [Introduction](#introduction)
- [The Types of Associations](#the-types-of-associations)
    - [BelongsTo](#belongsto)
    - [HasMany](#hasmany)
    - [HasManyThrough](#hasmanythrough)
    - [HasOne](#hasone)
    - [HasOneThrough](#hasonethrough)
    - [Choosing Between BelongsTo and HasOne](#choosing-between-belongsto-and-hasone)
    - [Self Joins](#self-joins)
- [Associations and the Database Schema](#associations-and-the-database-schema)
- [Detailed Association Reference](#detailed-association-reference)
    - [BelongsTo Reference](#belongsto-reference)


## Introduction

**An association is a connection between two [Record](http://github.com/groue/GRDB.swift#records) types.** It helps your code perform common operations in an easier way.

For example, consider an application that defines two record types for authors and books. Each author can have many books:

```swift
struct Author: TableMapping, RowConvertible { ... }
struct Book: TableMapping, RowConvertible { ... }
```

> :point_up: **Note**: See the [Records Protocol Overview] for more information about TableMapping and RowConvertible record protocols.

Without associations, fetching books from authors would look like:

```swift
// All books written by an author:
let author: Author = ...
let books: [Book] = try Book
    .filter(Book.Columns.authorId == author.id)
    .fetchAll(db)

// All authors with their books:
let authors = try Author.fetchAll(db)
let allAuthorsWithTheirBooks: [(Author, [Book])] = try authors.map { author in
    let books = try Book
        .filter(Book.Columns.authorId == author.id)
        .fetchAll(db)
    return (author, books)
}
```

With associations, this code can be streamlined:

```swift
// Declare the association from authors to their books:
extension Author {
    static let books = hasMany(Book.self)
}

// All books written by an author:
let author: Author = ...
let books: [Book] = try author.fetchAll(db, Author.books)

// All authors with their books:
let allAuthorsWithTheirBooks: [(Author, [Book])] = Author
    .including(Author.books)
    .fetchAll(db)
```

Associations bring more APIs that involve several associated record types. We'll introduce below the various kinds of associations, and then provide the reference to their methods and options.


The Types of Associations
=========================

GRDB handles five types of associations:

- BelongsTo
- HasOne
- HasMany
- HasOneThrough
- HasManyThrough

An association declares a link from a record type to another, as in "one book *belongs to* its author". It instructs GRDB to use the foreign keys declared in the database as support for Swift methods.

Each one of the five types of associations is appropriate for a particular database situation.


## BelongsTo

The *BelongsTo* association sets up a one-to-one connection from a record type to another record type, such as each instance of the declaring record "belongs to" an instance of the other record.

For example, if your application includes authors and books, and each book is assigned its author, you'd declare the association this way:

```swift
struct Book: TableMapping {
    // When books always have an author in the database:
    static let author = belongsTo(Author.self)
    
    // When some books don't have any author in the database:
    static let author = belongsTo(optional: Author.self)
    ...
}

struct Author: TableMapping {
    ...
}
```

A book **belongs to** its author:

![BelongsToDatabase](https://cdn.rawgit.com/groue/GRDB.swift/Graph/Documentation/Images/BelongsToDatabase.svg)

¹ `authorId` is a *foreign key* to the `authors` table.

The matching [migration] would look like:

```swift
migrator.registerMigration("Books and Authors") { db in
    try db.create(table: "authors") { t in
        t.column("id", .integer).primaryKey()
        t.column("name", .text)
    }
    try db.create(table: "books") { t in
        t.column("id", .integer).primaryKey()
        t.column("authorId", .integer)
            .notNull() // When books always have an author in the database
            .references("authors", onDelete: .cascade)
        t.column("title", .text)
    }
}
```


## HasOne

The *HasOne* association also sets up a one-to-one connection from a record type to another record type, but with different semantics, and underlying database schema. It is usually used when an entity has been denormalized into two database tables.

For example, if your application has one database table for countries, and another for their demographic profiles, you'd declare the association this way:

```swift
struct Country: TableMapping {
    // When countries always have a profile in the database:
    static let profile = hasOne(DemographicProfile.self)
    
    // When some countries don't have any profile in the database:
    static let profile = hasOne(optional: DemographicProfile.self)
    ...
}

struct DemographicProfile: TableMapping {
    ...
}
```

A country **has one** demographic profile:

![HasOneDatabase](https://cdn.rawgit.com/groue/GRDB.swift/Graph/Documentation/Images/HasOneDatabase.svg)

¹ `countryCode` is a *foreign key* to the `countries` table. It is *uniquely indexed* to guarantee the unicity of a country's profile.

The matching [migration] would look like:

```swift
migrator.registerMigration("Countries and DemographicProfiles") { db in
    try db.create(table: "countries") { t in
        t.column("code", .text).primaryKey()
        t.column("name", .text)
    }
    try db.create(table: "demographicProfiles") { t in
        t.column("id", .integer).primaryKey()
        t.column("countryCode", .text)
            .unique()
            .references("countries", onDelete: .cascade)
        t.column("population", .integer)
        t.column("density", .double)
    }
}
```


## HasMany

The *HasMany* association indicates a one-to-many connection between two record types, such as each instance of the declaring record "has many" instances of the other record. You'll often find this association on the other side of a *BelongsTo* association.

For example, if your application includes authors and books, and each author is assigned zero or more books, you'd declare the association this way:

```swift
struct Author: TableMapping {
    static let books = hasMany(Book.self)
}

struct Book: TableMapping {
    ...
}
```

An author **has many** books:

![HasManyDatabase](https://cdn.rawgit.com/groue/GRDB.swift/Graph/Documentation/Images/HasManyDatabase.svg)

¹ `authorId` is a *foreign key* to the `authors` table. It should be *indexed* to ease the selection of books belonging to a specific author.

The matching [migration] would look like:

```swift
migrator.registerMigration("Books and Authors") { db in
    try db.create(table: "authors") { t in
        t.column("id", .integer).primaryKey()
        t.column("name", .text)
    }
    try db.create(table: "books") { t in
        t.column("id", .integer).primaryKey()
        t.column("authorId", .integer)
            .indexed()
            .references("authors", onDelete: .cascade)
        t.column("title", .text)
    }
}
```


## HasManyThrough

The *HasManyThrough* association sets up a one-to-many connection between two record types, *through* a third record. You declare this association by linking two other associations together.

For example, consider an application that includes countries, passports, and citizens. You'd declare a *HasManyThrough* association between a country and its citizens through passports. To declare that association, link the *HasMany* association from countries to passports, and the *BelongsTo* association from passports to citizens:

```swift
struct Country: TableMapping {
    static let passports = hasMany(Passport.self)
    static let citizens = hasMany(Passport.citizen, through: passports)
    ...
}

struct Passport: TableMapping {
    static let citizen = belongsTo(Citizen.self)
    ...
}

struct Citizen: TableMapping {
    ...
}
```

A country **has many** citizens **through** passports:

![HasManyThroughDatabase](https://cdn.rawgit.com/groue/GRDB.swift/Graph/Documentation/Images/HasManyThroughDatabase.svg)

¹ `countryCode` is a *foreign key* to the `countries` table.

² `citizenId` is a *foreign key* to the `citizens` table.

The matching [migration] would look like:

```swift
migrator.registerMigration("Countries, Passports, and Citizens") { db in
    try db.create(table: "countries") { t in
        t.column("code", .text).primaryKey()
        t.column("name", .text)
    }
    try db.create(table: "citizens") { t in
        t.column("id", .integer).primaryKey()
        t.column("name", .text)
    }
    try db.create(table: "passports") { t in
        t.column("countryCode", .text)
            .notNull()
            .references("countries", onDelete: .cascade)
        t.column("citizenId", .text)
            .notNull()
            .references("citizens", onDelete: .cascade)
        t.primaryKey(["countryCode", "citizenId"])
        t.column("issueDate", .date)
    }
}
```

> :point_up: **Note**: the example above defines a *HasManyThrough* association by linking a *HasMany* association and a *BelongsTo* association. In general, any two associations that share the same intermediate type can be used to define a *HasManyThrough* association.


## HasOneThrough

The *HasOneThrough* association sets up a one-to-one connection between two record types, *through* a third record. You declare this association by linking two other one-to-one associations together.

For example, consider an application that includes books, libraries, and addresses. You'd declare that each book has a return address by linking the *BelongsTo* association from books to libraries, and the *HasOne* association from libraries to their addresses:

```swift
struct Book: TableMapping {
    static let library = belongsTo(Library.self)
    static let returnAddress = hasOne(Library.address, through: library)
    ...
}

struct Library: TableMapping {
    static let address = hasOne(Address.self)
    ...
}

struct Address: TableMapping {
    ...
}
```

A book **has one** return address **through** its library:

![HasOneThroughDatabase](https://cdn.rawgit.com/groue/GRDB.swift/Graph/Documentation/Images/HasOneThroughDatabase.svg)

¹ `libraryId` is a *foreign key* to the `libraries` table.

² `libraryId` is both the *primary key* of the `addresses` table, and a *foreign key* to the `libraries` table.

The matching [migration] would look like:

```swift
migrator.registerMigration("Books, Libraries, and Addresses") { db in
    try db.create(table: "libraries") { t in
        t.column("id", .integer).primaryKey()
        t.column("name", .text)
    }
    try db.create(table: "books") { t in
        t.column("id", .integer).primaryKey()
        t.column("libraryId", .integer)
            .notNull()
            .references("libraries", onDelete: .cascade)
        t.column("title", .text).primaryKey()
    }
    try db.create(table: "addresses") { t in
        t.column("libraryId", .integer)
            .primaryKey()
            .references("libraries", onDelete: .cascade)
        t.column("street", .text)
        t.column("city", .text)
    }
}
```

> :point_up: **Note**: the example above defines a *HasOneThrough* association by linking a *BelongsTo* association and a *HasOne* association. In general, any two non-optional one-to-one associations that share the same intermediate type can be used to define a *HasOneThrough* association. When one or both of the linked associations is optional, you build a *HasOneOptionalThrough* association.


## Choosing Between BelongsTo and HasOne

When you want to set up a one-to-one relationship between two record types, you'll need to add a *BelongsTo* association to one, and a *HasOne* association to the other. How do you know which is which?

The distinction is in where you place the database foreign key. The record that points to the other one has the *BelongsTo* association. The other record has the *HasOne* association:

A demographic profile **belongs to** a country, and a country **has one** demographic profile:

![HasOneDatabase](https://cdn.rawgit.com/groue/GRDB.swift/Graph/Documentation/Images/HasOneDatabase.svg)

```swift
struct Country: TableMapping, RowConvertible {
    static let profile = hasOne(DemographicProfile.self)
    ...
}

struct DemographicProfile: TableMapping, RowConvertible {
    static let country = belongsTo(DemographicProfile.self)
    ...
}
```


## Self-Joining Associations

In designing a database schema, you will sometimes find a record that should have a relation to itself. For example, you may want to store all employees in a single database table, but be able to trace relationships such as between manager and subordinates. This situation can be modeled with self-joining associations:

```swift
struct Employee: TableMapping {
    static let manager = belongsTo(optional: Employee.self)
    static let subordinates = hasMany(Employee.self)
    ...
}
```

![SelfJoinSchema](https://cdn.rawgit.com/groue/GRDB.swift/Graph/Documentation/Images/SelfJoinSchema.svg)

The matching [migration] would look like:

```swift
migrator.registerMigration("Employees") { db in
    try db.create(table: "employees") { t in
        t.column("id", .integer).primaryKey()
        t.column("managerId", .integer)
            .indexed()
            .references("employees", onDelete: .setNull)
        t.column("name", .text)
    }
}
```


Associations and the Database Schema
====================================

In all examples above, we have defined associations without giving the name of any database column:

```swift
struct Author: TableMapping {
    static let books = hasMany(Book.self)
}

struct Book: TableMapping {
    static let author = belongsTo(Author.self)
}
```

This concise definition of association is possible when the database schema defines without any ambiguity the foreign and primary keys that support the association. For example, in the migration below, the `authors` table has a primary key, and the `books` table has a foreign key:

```swift
migrator.registerMigration("Books and Authors") { db in
    try db.create(table: "authors") { t in
        t.column("id", .integer).primaryKey() // primary key
        t.column("name", .text)
    }
    try db.create(table: "books") { t in
        t.column("id", .integer).primaryKey()
        t.column("authorId", .integer)        // foreign key
            .notNull()
            .indexed()
            .references("authors", onDelete: .cascade)
        t.column("title", .text)
    }
}
```

Yet sometimes the database schema is ambiguous. This happens when a table defines several foreign keys to another table. This also happens when the schema is loose, and does not define any foreign or primary key at all.

In this case, you must help associations using the proper columns:

- Either by providing the column(s) that point to the primary key of the other table:
    
    ```swift
    struct Author: TableMapping {
        static let books = hasMany(Book.self, using: ForeignKey(["authorId"]))
    }
    
    struct Book: TableMapping {
        static let author = belongsTo(Author.self, using: ForeignKey(["authorId"]))
    }
    ```

- Or by providing the full definition of the foreign key:

    ```swift
    struct Author: TableMapping {
        static let books = hasMany(Book.self, using: ForeignKey(["authorId"], to: ["id"]))
    }
    
    struct Book: TableMapping {
        static let author = belongsTo(Author.self, using: ForeignKey(["authorId"], to: ["id"]))
    }
    ```
    

Foreign keys can also be defined from columns of type `Column`:

```swift
struct Author: TableMapping {
    static let books = hasMany(Book.self, using: Book.ForeignKeys.author)
}

struct Book: TableMapping {
    enum Columns {
        static let authorId = Column("authorId")
    }
    enum ForeignKeys {
        static let author = ForeignKey([Columns.authorId]))
    }
    static let author = belongsTo(Author.self, using: ForeignKeys.author)
}
```

> :point_up: **Note**: explicit association columns are always defined with a *foreign key* from a database table to another. That foreign key is independent from the orientation of the associations, and that's why you'll use the same foreign key for both an association and its reciprocal, as in the *BelongsTo/HasMany* examples above.


Detailed Association Reference
==============================

The following sections give the details of each type of association, including the methods that they define, and the options that you can use when declaring an association.


## BelongsTo Reference

The *BelongsTo* association sets up a one-to-one connection from a record type to another record type. In database terms, this association says that the record type that declares the association contains the foreign key. If the other record contains the foreign key, then you should use *HasOne* instead.


### Declaring the Association

To declare a *BelongsTo* association, you use one of those static methods:

- `belongsTo(_:using:)`
- `belongsTo(optional:using:)`

The first argument is the type of the targetted record.

The `optional:` variant declares that the database may not always contain a matching record. You can think of it as the Swift `Optional` type: just as a Swift optional tells that a value may be missing, `belongsTo(optional:)` tells that an associated record may be missing in the database.

The second `using:` argument is a foreign key that is only necessary when GRDB can't automatically infer the columns that supports the association from the database schema (see [Associations and the Database Schema](#associations-and-the-database-schema)).

For example:

```swift
struct Book: TableMapping {
    // When books always have an author in the database:
    static let author = belongsTo(Author.self)
    
    // When some books don't have any author in the database:
    static let author = belongsTo(optional: Author.self)
    ...
}

struct Author: TableMapping {
    ...
}
```


### Using the Association

The *BelongsTo* association adds three methods to the declaring Record:

- `Record.including(_:)`
- `Record.join(_:)`
- `record.fetchOne(_:_:)`


#### `Record.including(_:)`

The `including(_:)` static method returns a request that fetches all associated pairs as Swift tuples:

```swift
struct Author: TableMapping, RowConvertible {
    ...
}

struct Book: TableMapping, RowConvertible {
    static let author = belongsTo(Author.self)
    ...
}

try dbQueue.inDatabase { db in
    let request = Book.including(Book.author)
    let results = try request.fetchAll(db) // [(Book, Author)]
}
```

When the association is declared with the `optional:` variant, the right object of the tuple is optional:

```swift
struct Book: TableMapping, RowConvertible {
    static let author = belongsTo(optional: Author.self)
    ...
}

try dbQueue.inDatabase { db in
    let request = Book.including(Book.author)
    let results = try request.fetchAll(db) // [(Book, Author?)]
}
```

You fetch all associated pairs as an Array with `fetchAll`, as a [cursor] with `fetchCursor`, or you can fetch the first one with `fetchOne`. See [Fetching Methods](https://github.com/groue/GRDB.swift/blob/master/README.md#fetching-methods) for more information:

```swift
try dbQueue.inDatabase { db in
    let request = Book.including(Book.author)
    try request.fetchCursor(db) // A cursor of (Book, Author) or (Book, Author?)
    try request.fetchAll(db)    // [(Book, Author)] or [(Book, Author?)]
    try request.fetchOne(db)    // (Book, Author)? or (Book, Author?)?
}
```

##### Filtering, Ordering, Aliasing

The request returned by `including(_:)` can be further refined just like other [Query Interface Requests](https://github.com/groue/GRDB.swift/blob/master/README.md#requests) with the `filter` and `order` methods. In this case, filtering and ordering apply to the main record (here, Book):

```swift
// The ten cheapest thrillers, with their author:
try dbQueue.inDatabase { db in
    let request = Book
        .including(Book.author)
        .filter(Book.Columns.genre == "Thriller")
        .order(Book.Columns.price)
        .limit(10)
    let results = try request.fetchAll(db) // [(Book, Author)] or [(Book, Author?)]
}
```

You can also refine the association. In this case, the results depend on whether the association is optional or not.

Filtering a non-optional association reduces the number of results, in order to fetch non-nil associated records:

```swift
struct Book: TableMapping, RowConvertible {
    static let author = belongsTo(Author.self) // Non optional association
    ...
}

// All books by French authors
try dbQueue.inDatabase { db in
    let frenchAuthors = Book.author.filter(Author.Columns.countryCode == "FR")
    let request = Book
        .including(frenchAuthors)
        .order(Book.Columns.title)
    let results = try request.fetchAll(db) // [(Book, Author)]
}
```

Conversely, filtering an optional association does not reduce the number of results. Instead, more results have a nil associated record. TODO: this is bullshit. What can be the purpose of such a behavior? I know that LEFT JOIN works this way. But should associations do???


#### `Record.join(_:)`

- [ ] **TODO**


#### `record.fetchOne(_:_:)`

The `fetchOne(_:_:)` instance method fetches the associated record:

```swift
try dbQueue.inDatabase { db in
    let book: Book = ...
    let author = try book.fetchOne(db, Book.author) // Author?
}
```

The fetched record is an optional even if the association has not been declared with the `optional:` variant.


### Refining the Association

- [ ] **TODO**

[cursor]: https://github.com/groue/GRDB.swift/blob/master/README.md#cursors
[migration]: https://github.com/groue/GRDB.swift/blob/master/README.md#migrations
[Records Protocol Overview]: https://github.com/groue/GRDB.swift/blob/master/README.md#record-protocols-overview
