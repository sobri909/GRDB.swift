GRDB Associations
=================

- [Associations Benefits]
- [The Types of Associations]
    - [BelongsTo]
    - [HasOne]
    - [HasMany]
    - [Choosing Between BelongsTo and HasOne]
    - [Self Joins]
- [Associations and the Database Schema]
    - [Convention for Database Table Names]
    - [Convention for the BelongsTo Association]
    - [Convention for the HasOne Association]
    - [Convention for the HasMany Association]
    - [Foreign Keys]
- [Building Requests from Associations]
    - [Requesting Associated Records]
    - [Joining Methods]
    - [Combining Associations]
    - [Filtering Associations]
    - [Sorting Associations]
    - [Table Aliases]
- [Fetching Values from Associations]
    - [The Structure of a Joined Request]
    - [Decoding a Joined Request with a Decodable Record]
    - [Decoding a Joined Request with FetchableRecord]
- [Future Directions]


## Associations Benefits

**An association is a connection between two [Record] types.**

Associations streamline common operations in your code, make them safer, and more efficient. For example, consider a library application that has two record types, author and book:

```swift
struct Author: TableRecord, FetchableRecord {
    var id: Int64
    var name: String
}

struct Book: TableRecord, FetchableRecord {
    var id: Int64
    var authorId: Int64?
    var title: String
}
```

Now, suppose we wanted to load all books from an existing author. We'd need to do something like this:

```swift
let author: Author = ...
let books = try Book
    .filter(Column("authorId") == author.id)
    .fetchAll(db)
```

Or, loading all pairs of books along with their authors:

```swift
struct BookInfo {
    var book: Book
    var author: Author?
}

let books = try Book.fetchAll(db)
let bookInfos = books.map { book -> BookInfo in
    let author = try Author.fetchOne(key: book.authorId)
    return BookInfo(book: book, author: author)
}
```

With GRDB associations, we can streamline these operations (and others), by declaring the connections between books and authors. Here is how we define those associations:

```swift
struct Author: TableRecord, FetchableRecord {
    static let books = hasMany(Book.self)      // <-
    var id: Int64
    var name: String
}

struct Book: TableRecord, FetchableRecord {
    static let author = belongsTo(Author.self) // <-
    var id: Int64
    var authorId: Int64?
    var title: String
}
```

Loading all books from an existing author is now easier:

```swift
let books = try author.fetchAll(db, Author.books)
```

As for loading all pairs of books and authors, it is not only easier, but also *far much efficient*:

```swift
struct BookInfo: FetchableRecord, Codable {
    let book: Book
    let author: Author?
}

let request = Book.including(optional: Book.author)
let bookInfos = BookInfo.fetchAll(db, request)
```


The Types of Associations
=========================

GRDB handles three types of associations:

- [BelongsTo]
- [HasOne]
- [HasMany]

An association declares a link from a record type to another, as in "one book *belongs to* its author". It instructs GRDB to use the foreign keys declared in the database as support for Swift methods.

Each one of the three types of associations is appropriate for a particular database situation.

- [BelongsTo]
- [HasOne]
- [HasMany]
- [Choosing Between BelongsTo and HasOne]
- [Self Joins]


## BelongsTo

The *BelongsTo* association sets up a one-to-one connection from a record type to another record type, such as each instance of the declaring record "belongs to" an instance of the other record.

For example, if your application includes authors and books, and each book is assigned its author, you'd declare the association this way:

```swift
struct Book: TableRecord {
    static let author = belongsTo(Author.self)
    ...
}

struct Author: TableRecord {
    ...
}
```

The BelongsTo association between a book and its author needs that the database table for books has a column that points to the table for authors:

![BelongsToSchema](https://cdn.rawgit.com/groue/GRDB.swift/GRDB3-Associations/Documentation/Images/Associations2/BelongsToSchema.svg)

See [Convention for the BelongsTo Association] for some sample code that defines the database schema for such an association.


## HasOne

The *HasOne* association also sets up a one-to-one connection from a record type to another record type, but with different semantics, and underlying database schema. It is usually used when an entity has been denormalized into two database tables.

For example, if your application has one database table for countries, and another for their demographic profiles, you'd declare the association this way:

```swift
struct Country: TableRecord {
    static let demographics = hasOne(Demographics.self)
    ...
}

struct Demographics: TableRecord {
    ...
}
```

The HasOne association between a country and its demographics needs that the database table for demographics has a column that points to the table for countries:

![HasOneSchema](https://cdn.rawgit.com/groue/GRDB.swift/GRDB3-Associations/Documentation/Images/Associations2/HasOneSchema.svg)

See [Convention for the HasOne Association] for some sample code that defines the database schema for such an association.


## HasMany

The *HasMany* association indicates a one-to-many connection between two record types, such as each instance of the declaring record "has many" instances of the other record. You'll often find this association on the other side of a *BelongsTo* association.

For example, if your application includes authors and books, and each author is assigned zero or more books, you'd declare the association this way:

```swift
struct Author: TableRecord {
    static let books = hasMany(Book.self)
}

struct Book: TableRecord {
    ...
}
```

The HasMany association between an author and its books needs that the database table for books has a column that points to the table for authors:

![HasManySchema](https://cdn.rawgit.com/groue/GRDB.swift/GRDB3-Associations/Documentation/Images/Associations2/HasManySchema.svg)

See [Convention for the HasMany Association] for some sample code that defines the database schema for such an association.


## Choosing Between BelongsTo and HasOne

When you want to set up a one-to-one relationship between two record types, you'll need to add a *BelongsTo* association to one, and a *HasOne* association to the other. How do you know which is which?

The distinction is in where you place the database foreign key. The record that points to the other one has the *BelongsTo* association. The other record has the *HasOne* association:

A country **has one** demographic profile, a demographic profile **belongs to** a country:

![HasOneSchema](https://cdn.rawgit.com/groue/GRDB.swift/GRDB3-Associations/Documentation/Images/Associations2/HasOneSchema.svg)

```swift
struct Country: TableRecord, FetchableRecord {
    static let demographics = hasOne(Demographics.self)
    ...
}

struct Demographics: TableRecord, FetchableRecord {
    static let country = belongsTo(Demographics.self)
    ...
}
```

## Self Joins

When designing your data model, you will sometimes find a record that should have a relation to itself. For example, you may want to store all employees in a single database table, but be able to trace relationships such as between manager and subordinates. This situation can be modeled with self-joining associations:

```swift
struct Employee {
    static let subordinates = hasMany(Employee.self)
    static let manager = belongsTo(Employee.self)
}
```

![RecursiveSchema](https://cdn.rawgit.com/groue/GRDB.swift/GRDB3-Associations/Documentation/Images/Associations2/RecursiveSchema.svg)

The matching [migration] would look like:

```swift
migrator.registerMigration("Employees") { db in
    try db.create(table: "employee") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("managerId", .integer)
            .indexed()
            .references("employee", onDelete: .restrict)
        t.column("name", .text)
    }
}
```


Associations and the Database Schema
====================================

**Associations are grounded in the database schema, the way database tables are defined.**

For example, a [BelongsTo] association between a book and its author needs that the database table for books has a column that points to the table for authors.

GRDB also comes with several *conventions* for defining your database schema.

Those conventions help associations be convenient and, generally, "just work". When you can't, or don't want to follow conventions, you will have to override the expected defaults in your Swift code.

- [Convention for Database Table Names]
- [Convention for the BelongsTo Association]
- [Convention for the HasOne Association]
- [Convention for the HasMany Association]
- [Foreign Keys]


## Convention for Database Table Names

**Database table names should be singular and camel-cased.**

This is the same convention as Swift identifiers for variables and properties. For example: `book`, `author`, `postalAddress`.

This convention helps fetching values from associations. It is used, for example, in the sample code below, where we load all pairs of books along with their authors:

```swift
// The Book record
struct Book: FetchableRecord, TableRecord {
    static let databaseTableName = "book"
    static let author = belongsTo(Author.self)
    ...
}

// The Author record
struct Author: FetchableRecord, TableRecord {
    static let databaseTableName = "author"
    ...
}

// A pair made of a book and its author
struct BookInfo: FetchableRecord, Codable {
    let book: Book
    let author: Author?
}

let request = Book.including(optional: Book.author)
let bookInfos = BookInfo.fetchAll(db, request)
```

This sample code only works if the database table for authors is called "author". This name "author" is the key that helps BookInfo initialize its `author` property.

If the database schema does not follow this convention, and has, for example, database tables named with plural names (`authors` and `books`), you can still use associations. But you need to help row consumption by providing the required key:

```swift
struct Book: FetchableRecord, TableRecord {
    static let author = belongsTo(Author.self).forKey("author") // <-
}
```

See [The Structure of a Joined Request] for more information.


## Convention for the BelongsTo Association

**[BelongsTo] associations should be supported by an SQLite foreign key.**

Foreign keys are the recommended way to declare relationships between database tables. Not only will SQLite guarantee the integrity of your data, but GRDB will be able to use those foreign keys to automatically configure your associations.

![BelongsToSchema](https://cdn.rawgit.com/groue/GRDB.swift/GRDB3-Associations/Documentation/Images/Associations2/BelongsToSchema.svg)

The matching [migration] could look like:

```swift
migrator.registerMigration("Books and Authors") { db in
    try db.create(table: "author") { t in
        t.autoIncrementedPrimaryKey("id")             // (1)
        t.column("name", .text)
    }
    try db.create(table: "book") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("authorId", .integer)                // (2)
            .notNull()                                // (3)
            .indexed()                                // (4)
            .references("author", onDelete: .cascade) // (5)
        t.column("title", .text)
    }
}
```

1. The `author` table has a primary key.
2. The `book.authorId` column is used to link a book to the author it belongs to.
3. Make the `book.authorId` column not null if you want SQLite to guarantee that all books have an author.
4. Create an index on the `book.authorId` column in order to ease the selection of an author's books.
5. Create a foreign key from `book.authorId` column to `authors.id`, so that SQLite guarantees that no book refers to a missing author. The `onDelete: .cascade` option has SQLite automatically delete all of an author's books when that author is deleted. See [Foreign Key Actions] for more information.

The example above uses auto-incremented primary keys. But generally speaking, all primary keys are supported.

Following this convention lets you write, for example:

```swift
struct Book: FetchableRecord, TableRecord {
    static let databaseTableName = "book"
    static let author = belongsTo(Author.self)
}

struct Author: FetchableRecord, TableRecord {
    static let databaseTableName = "author"
}
```

If the database schema does not follow this convention, and does not define foreign keys between tables, you can still use BelongsTo associations. But your help is needed to define the missing foreign key:

```swift
struct Book: FetchableRecord, TableRecord {
    static let author = belongsTo(Author.self, using: ForeignKey(...))
}
```

See [Foreign Keys] for more information.


## Convention for the HasOne Association

**[HasOne] associations should be supported by an SQLite foreign key.**

Foreign keys are the recommended way to declare relationships between database tables. Not only will SQLite guarantee the integrity of your data, but GRDB will be able to use those foreign keys to automatically configure your associations.

![HasOneSchema](https://cdn.rawgit.com/groue/GRDB.swift/GRDB3-Associations/Documentation/Images/Associations2/HasOneSchema.svg)

The matching [migration] could look like:

```swift
migrator.registerMigration("Countries") { db in
    try db.create(table: "country") { t in
        t.column("code", .text).primaryKey()           // (1)
        t.column("name", .text)
    }
    try db.create(table: "demographics") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("countryCode", .text)                 // (2)
            .notNull()                                 // (3)
            .unique()                                  // (4)
            .references("country", onDelete: .cascade) // (5)
        t.column("population", .integer)
        t.column("density", .double)
    }
}
```

1. The `country` table has a primary key.
2. The `demographics.countryCode` column is used to link a demographic profile to the country it belongs to.
3. Make the `demographics.countryCode` column not null if you want SQLite to guarantee that all profiles are linked to a country.
4. Create a unique index on the `demographics.countryCode` column in order to guarantee the unicity of any country's profile.
5. Create a foreign key from `demographics.countryCode` column to `country.code`, so that SQLite guarantees that no profile refers to a missing country. The `onDelete: .cascade` option has SQLite automatically delete a profile when its country is deleted. See [Foreign Key Actions] for more information.

The example above uses a string primary key for the "country" table. But generally speaking, all primary keys are supported.

Following this convention lets you write, for example:

```swift
struct Country: FetchableRecord, TableRecord {
    static let databaseTableName = "country"
    static let demographics = hasOne(Demographics.self)
}

struct Demographics: FetchableRecord, TableRecord {
    static let databaseTableName = "demographics"
}
```

If the database schema does not follow this convention, and does not define foreign keys between tables, you can still use HasOne associations. But your help is needed to define the missing foreign key:

```swift
struct Book: FetchableRecord, TableRecord {
    static let demographics = hasOne(Demographics.self, using: ForeignKey(...))
}
```

See [Foreign Keys] for more information.


## Convention for the HasMany Association

**[HasMany] associations should be supported by an SQLite foreign key.**

Foreign keys are the recommended way to declare relationships between database tables. Not only will SQLite guarantee the integrity of your data, but GRDB will be able to use those foreign keys to automatically configure your associations.

![HasManySchema](https://cdn.rawgit.com/groue/GRDB.swift/GRDB3-Associations/Documentation/Images/Associations2/HasManySchema.svg)

The matching [migration] could look like:

```swift
migrator.registerMigration("Books and Authors") { db in
    try db.create(table: "author") { t in
        t.autoIncrementedPrimaryKey("id")             // (1)
        t.column("name", .text)
    }
    try db.create(table: "book") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("authorId", .integer)                // (2)
            .notNull()                                // (3)
            .indexed()                                // (4)
            .references("author", onDelete: .cascade) // (5)
        t.column("title", .text)
    }
}
```

1. The `author` table has a primary key.
2. The `book.authorId` column is used to link a book to the author it belongs to.
3. Make the `book.authorId` column not null if you want SQLite to guarantee that all books have an author.
4. Create an index on the `book.authorId` column in order to ease the selection of an author's books.
5. Create a foreign key from `book.authorId` column to `authors.id`, so that SQLite guarantees that no book refers to a missing author. The `onDelete: .cascade` option has SQLite automatically delete all of an author's books when that author is deleted. See [Foreign Key Actions] for more information.

The example above uses auto-incremented primary keys. But generally speaking, all primary keys are supported.

Following this convention lets you write, for example:

```swift
struct Book: FetchableRecord, TableRecord {
    static let databaseTableName = "book"
}

struct Author: FetchableRecord, TableRecord {
    static let databaseTableName = "author"
    static let books = hasMany(Book.self)
}
```

If the database schema does not follow this convention, and does not define foreign keys between tables, you can still use HasMany associations. But your help is needed to define the missing foreign key:

```swift
struct Author: FetchableRecord, TableRecord {
    static let books = hasMany(Book.self, using: ForeignKey(...))
}
```

See [Foreign Keys] for more information.


## Foreign Keys

**Associations can automatically infer the foreign keys that define how two database tables are linked together.**

In the example below, the `book.authorId` column is automatically used to link a book to its author:

![BelongsToSchema](https://cdn.rawgit.com/groue/GRDB.swift/GRDB3-Associations/Documentation/Images/Associations2/BelongsToSchema.svg)

```swift
struct Book: TableRecord {
    static let author = belongsTo(Author.self)
}

struct Author: TableRecord {
    static let books = hasMany(Book.self)
}
```

But this requires the database schema to define a foreign key between the book and author database tables (see [Convention for the BelongsTo Association]).

Sometimes the database schema does not define any foreign key. And sometimes, there are *several* foreign keys from a table to another.

![AmbiguousForeignKeys](https://cdn.rawgit.com/groue/GRDB.swift/GRDB3-Associations/Documentation/Images/Associations2/AmbiguousForeignKeys.svg)

When this happens to you, you'll know it: GRDB will complain with fatal errors such as "Ambiguous foreign key from book to author", or "Could not infer foreign key from book to author".

Your help is needed to avoid those errors:

```swift
struct Book: TableRecord {
    // Define foreign keys
    enum ForeignKeys {
        static let author = ForeignKey(["authorId"]))
        static let translator = ForeignKey(["translatorId"]))
    }
    
    // Use foreign keys to define associations:
    static let author = belongsTo(Person.self, using: ForeignKeys.author)
    static let translator = belongsTo(Person.self, using: ForeignKeys.translator)
}
```

The definition of Person's hasMany associations can reuse Book's foreign keys:

```swift
struct Person: TableRecord {
    static let writtenBooks = hasMany(Book.self, using: Book.ForeignKeys.author)
    static let translatedBooks = hasMany(Book.self, using: Book.ForeignKeys.translator)
}
```

Foreign keys can also be defined from `Column`:

```swift
struct Book: TableRecord {
    enum Columns {
        static let authorId = Column("authorId")
        static let translatorId = Column("translatorId")
    }
    enum ForeignKeys {
        static let author = ForeignKey([Columns.authorId]))
        static let translator = ForeignKey([Columns.translatorId]))
    }
}
```

When the destination table of a foreign key does not define any primary key, you need to provide the full definition of a foreign key:

```swift
struct Book: TableRecord {
    enum ForeignKeys {
        static let author = ForeignKey(["authorId"], to: ["id"]))
    }
    static let author = belongsTo(Person.self, using: ForeignKeys.author)
}
```


Building Requests from Associations
===================================

**Once you have defined associations, you can define fetch request that involve several record types.**

> :point_up: **Note**: Those requests are executed by SQLite as *SQL joined queries*. In all examples below, we'll show the SQL queries executed by our association-based requests. You can ignore them if you are not familiar with SQL.

Fetch requests do not visit the database until you fetch values from them. This will be covered in [Fetching Values from Associations]. But before you can fetch anything, you have to describe what you want to fetch. This is the topic of this chapter.

- [Requesting Associated Records]
- [Joining Methods]
- [Combining Associations]
- [Filtering Associations]
- [Sorting Associations]
- [Table Aliases]


## Requesting Associated Records

**You can use associations to build requests for associated records.**

For example, given a `Book.author` [BelongsTo] association, you can request and fetch the author of a book:

```swift
let book: Book = ...
let authorRequest = book.request(Book.author)     // QueryInterfaceRequest<Author>
let author = try authorRequest.fetchOne(db)       // Author?
let author = try book.fetchOne(db, Book.author)   // Author?
```

And given a `Author.books` [HasMany] associations, you can request and fetch the books of an author:

```swift
let author: Author = ...
let booksRequest = author.request(Author.books)   // QueryInterfaceRequest<Book>
let books = try booksRequest.fetchAll(db)         // [Book]
let books = try author.fetchAll(db, Author.books) // [Book]
```


## Joining Methods

**You build requests that involve several records with the four "joining methods":**

- `including(optional: association)`
- `including(required: association)`
- `joining(optional: association)`
- `joining(required: association)`

The `including` methods return requests that include the values of the associated record. On the other hand, the `joining` methods return requests that do not include the values of the associated record.

The `optional` variant return requests that allow the associated record to be missing. Conversely, the `required` variant return requests that filter results so that associated record is never missing.

Let's give a few examples, based on those two record types:

```swift
struct Book: TableRecord {
    static let author = belongsTo(Author.self)
}

struct Author: TableRecord {
}
```

These examples are based on the `Book.author` [BelongsTo] association, but everything that we will learn apply to other associations as well, [HasOne], and [HasMany].


### including(optional:)

```swift
// SELECT book.*, author.*
// FROM book
// LEFT JOIN author ON author.id = book.authorId
let request = Book.including(optional: Book.author)
```

This request fetches all books, including their author's information.

Books that don't have any author (a null `authorId` column) are fetched as well.


### including(required:)

```swift
// SELECT book.*, author.*
// FROM book
// JOIN author ON author.id = book.authorId
let request = Book.including(required: Book.author)
```

This request fetches all books, including their author's information.

Books that don't have any author (a null `authorId` column) are not fetched.


### joining(optional:)

```swift
// SELECT book.*
// FROM book
// LEFT JOIN author ON author.id = book.authorId
let request = Book.joining(optional: Book.author)
```

This request fetches all books.

Books that don't have any author (a null `authorId` column) are fetched as well.

This request is not much different from `Book.all()`. We'll see in [Combining Associations] and [Filtering Associations] how it can turn out useful.


### joining(required:)

```swift
// SELECT book.*
// FROM book
// JOIN author ON author.id = book.authorId
let request = Book.joining(required: Book.author)
```

This request fetches all books, but the books that don't have any author (a null `authorId` column).

This request is not much different from `Book.filter(authorId != nil)`. We'll see in [Combining Associations] and [Filtering Associations] how it can turn out useful.


## Combining Associations

**Associations can be combined in order to build more complex requests.**

You can join several associations in parallel:

```swift
// SELECT book.*, person1.*, person2.*
// FROM book
// JOIN person person1 ON person1.id = book.authorId
// LEFT JOIN person person2 ON person2.id = book.translatorId
let request = Book
    .including(required: Book.author)
    .including(optional: Book.translator)
```

The request above fetches all books, along with their author and eventual translator.

You can chain associations in order to jump from a record to another:

```swift
// SELECT book.*, person.*, country.*
// FROM book
// JOIN person ON person.id = book.authorId
// LEFT JOIN country ON country.code = person.countryCode
let request = Book
    .including(required: Book.author
        .including(optional: Person.country))
```

The request above fetches all books, along with their author, and their author's country.

When you chain associations, you can avoid fetching intermediate values by replacing the `including` method with `joining`:

```swift
// SELECT book.*, country.*
// FROM book
// LEFT JOIN person ON person.id = book.authorId
// LEFT JOIN country ON country.code = person.countryCode
let request = Book
    .joining(optional: Book.author
        .including(optional: Person.country))
```

The request above fetches all books, along with their author's country.

> :warning: **Warning**: you can not currently chain a required association behind an optional association:
>
> ```swift
> // Not implemented
> let request = Book
>     .joining(optional: Book.author
>         .including(required: Person.country))
> ```
>
> This code compiles, but you'll get a runtime fatal error "Not implemented: chaining a required association behind an optional association". Future versions of GRDB may allow such requests.


## Filtering Associations

**You can filter associated records.**

The `filter(_:)`, `filter(key:)` and `filter(keys:)` methods, that you already know for [filtering simple requests](https://github.com/groue/GRDB.swift/blob/GRDB3-Associations/README.md#requests), can filter associated records as well:

```swift
// SELECT book.*
// FROM book
// JOIN person ON person.id = book.authorId
//            AND person.countryCode = 'FR'
let frenchAuthor = Book.author.filter(Column("countryCode") == "FR")
let request = Book.joining(required: frenchAuthor)
```

The request above fetches all books written by a French author.

This example had us derive a filtered association from the raw `Book.author` association. You can also build an association right from a filtered request:

```swift
struct Book: TableRecord {
    static func author(from countryCode: String)
        -> BelongsToAssociation<Book, Person>
    {
        let filteredPeople = Person.filter(Column("countryCode") == countryCode)
        return belongsTo(filteredPeople)
    }
}

// The same request for all books written by a French author
let request = Book.joining(required: Book.author(from: "FR"))
```

> :warning: **Warning**: you can not currently define an association from a joined request.
>
> ```swift
> // Not implemented
> let peopleWithCountry = Person.including(required: Person.country)
> let authorWithCountry = Book.belongsTo(peopleWithCountry)
> let request = Book.including(required: authorWithCountry)
> ```
>
> This code compiles, but you'll get a runtime fatal error "Not implemented: defining associations from joined requests". Future versions of GRDB may allow such associations.


**There are more filtering options:**

- Filtering on conditions that involve several tables.
- Filtering in the WHERE clause instead of the ON clause (can be useful when you are skilled enough in SQL to make the difference).

Those extra filtering options require [Table Aliases], introduced below.


## Sorting Associations

**You can sort fetched results according to associated records.**

The `order()` method, that you already know for [sorting simple requests](https://github.com/groue/GRDB.swift/blob/GRDB3-Associations/README.md#requests), can sort associated records as well:

```swift
// SELECT book.*, person.*
// FROM book
// JOIN person ON person.id = book.authorId
// ORDER BY person.name
let sortedAuthor = Book.author.order(Column("name"))
let request = Book.including(required: sortedAuthor)
```

When you sort both the base record on the associated record, the request is sorted on the base record first, and on the associated record next:

```swift
// SELECT book.*, person.*
// FROM book
// JOIN person ON person.id = book.authorId
// ORDER BY book.publishDate DESC, person.name
let sortedAuthor = Book.author.order(Column("name"))
let request = Book
    .including(required: sortedAuthor)
    .order(Column("publishDate").desc)
```

**There are more sorting options:**

- Sorting on expressions that involve several tables.
- Changing the order of the sorting terms (such as sorting on author name first, and then publish date).

Those extra sorting options require [Table Aliases], introduced below.


## Table Aliases

In all examples we have seen so far, all associated records are joined, included, filtered, and sorted independently. We could not filter them on conditions that involve several records, for example.

Let's say we look for posthumous books, published after their author has died. We need to compare a book publication date with an author eventual death date.

Let's first see a wrong way to do it:

```swift
// A wrong request:
// SELECT book.*
// FROM book
// JOIN person ON person.id = book.authorId
// WHERE book.publishDate >= book.deathDate
let request = Book
    .joining(required: Book.author)
    .filter(Column("publishDate") >= Column("deathDate"))
```

When executed, we'll get a DatabaseError of code 1, "no such column: book.deathDate".

That is because the "deathDate" column has been used for filtering books, when it is defined on the person database table.

To fix this error, we need a *table alias*:

```swift
let authorAlias = TableAlias()
```

We modify the `Book.author` association so that it uses this table alias, and we use the table alias to qualify author columns where needed:

```swift
// SELECT book.*
// FROM book
// JOIN person ON person.id = book.authorId
// WHERE book.publishDate >= person.deathDate
let request = Book
    .joining(required: Book.author.aliased(authorAlias))
    .filter(Column("publishDate") >= authorAlias[Column("deathDate")])
```

Table aliases can also improve control over the ordering of request results. In the example below, we override the [default ordering](#sorting-associations) of associated records by sorting on author names first:

```swift
// SELECT book.*
// FROM book
// JOIN person ON person.id = book.authorId
// ORDER BY person.name, book.publishDate
let request = Book
    .joining(required: Book.author.aliased(authorAlias))
    .order(authorAlias[Column("name")], Column("publishDate"))
```

Table aliases can be given a name. This name is guaranteed to be used as the table alias in the SQL query. This guarantee lets you write SQL snippets when you need it:

```swift
// SELECT myBook.*
// FROM book myBook
// JOIN person myAuthor ON myAuthor.id = myBook.authorId
//                     AND myAuthor.countryCode = 'FR'
// WHERE myBook.publishDate >= myAuthor.deathDate
let bookAlias = TableAlias(name: "myBook")
let authorAlias = TableAlias(name: "myAuthor")
let request = Book.aliased(bookAlias)
    .joining(required: Book.author.aliased(authorAlias)
        .filter(sql: "myAuthor.countryCode = ?", arguments: ["FR"]))
    .filter(sql: "myBook.publishDate >= myAuthor.deathDate")
```


Fetching Values from Associations
=================================

We have seen in [Building Requests from Associations] how to define requests that involve several records by the mean of [Joining Methods].

If your application needs to display a list of book with information about their author, country, and cover image, you may build the following joined request:

```swift
// SELECT book.*, author.*, country.*, coverImage.*
// FROM book
// JOIN author ON author.id = book.authorId
// LEFT JOIN country ON country.code = author.countryCode
// LEFT JOIN coverImage ON coverImage.bookId = book.id
let request = Book
    .including(required: Book.author
        .including(optional: Author.country))
    .including(optional: Bool.coverImage)
```

**Now is the time to tell how joined requests should be consumed.**

As always in GRDB, requests can be consumed as raw database rows, or as well-structured and convenient records.

The request above can be consumed into the following record:

```swift
struct BookInfo: FetchableRecord, Decodable {
    var book: Book
    var author: Author
    var country: Country?
    var coverImage: CoverImage?
}

let bookInfos = try BookInfo.fetchAll(db, request) // [BookInfo]
```

If we consume raw rows, we start to see what's happening under the hood:

```swift
let row = try Row.fetchOne(db, request)! // Row
print(row.debugDescription)
// ▿ [id:1, authorId:2, title:"Moby-Dick"]
//   unadapted: [id:1, authorId:2, title:"Moby-Dick", id:2, name:"Herman Melville", countryCode:"US", code:"US", name:"United States of America", id:42, imageId:1, path:"moby-dick.jpg"]
//   - author: [id:2, name:"Herman Melville", countryCode:"US"]
//     - country: [code:"US", name:"United States of America"]
//   - coverImage: [id:42, imageId:1, path:"moby-dick.jpg"]
```

- [The Structure of a Joined Request]
- [Decoding a Joined Request with a Decodable Record]
- [Decoding a Joined Request with FetchableRecord]


## The Structure of a Joined Request

**Joined request define a tree of associated records identified by "association keys".**

Below, author and cover image are both associated to book, and country is associated to author:

```swift
let request = Book
    .including(required: Book.author
        .including(optional: Author.country))
    .including(optional: Bool.coverImage)
```

This request builds the following tree of association keys:

```
         root
           |
    +------+------+
    |             |
"author"     "coverImage"
    |
"country"
```

Association keys are strings. They are the names of the database tables of associated records (unless you specify otherwise, as we'll see below).

Those keys are associated with slices in the fetched rows:

```
      < root >
          |
          +-------+---------------------+
                  |                     |
              < author >           < coverImage >
                  |
                  +---------+
                            |
                        < country >
SELECT book.*, author.*, country.*, coverImage.*
FROM ...
```

We'll see below how this tree of association keys that map on row slices can feed a Decodable record type. We'll then add some details by using FetchableRecord without Decodable support.


## Decoding a Joined Request with a Decodable Record

When association keys match the property names of a Decodable record, you get free decoding of joined requests into this record:

```swift
struct BookInfo: FetchableRecord, Decodable {
    var book: Book
    var author: Author
    var country: Country?
    var coverImage: CoverImage?
}

let bookInfos = try BookInfo.fetchAll(db, request) // [BookInfo]
```

We see that a hierarchical tree has been flattened in the `BookInfo` record. Here is the precise algorithm applied when BookInfo decodes a database row:

The BookInfo initializer generated by the Decodable protocol requests the "book" key. This key is not found in the tree of association keys, so the book property is initialized from the fetched row. It happens that the fetched row contains book columns, because the request as been defined from the Book type: `Book.including(...)...`

The BookInfo initializer then requests the "author", "country", and "coverImage" keys. All those keys are found in the tree of association keys, so each property is initialized from the row slice associated with its key. It happens that those slices contain exactly the columns needed by each property type. When a slice contains only NULL values, an optional record is decoded as nil.

When a tree contains the same key several times, the key lookup resolves ambiguities by performing a breadth-first research (this means that deeply nested keys are always searched last).

You can also reflect the hierarchical structure of the request in the decodable record:

```swift
struct BookInfo: FetchableRecord, Decodable {
    struct AuthorInfo: Decodable {
        var author: Author
        var country: Country?
    }
    var book: Book
    var authorInfo: AuthorInfo
    var coverImage: CoverImage?
}
```

This type needs a slight modification to the original request, because there is no "authorInfo" association key that could feed the `authorInfo` property.

The Swift compiler grants Decodable types with a `CodingKeys` enum that knows everything about a type's properties. Cooding keys give us a safe way to define our modified request:

```swift
extension BookInfo {
    static func all() -> AnyRequest<BookInfo> {
        return Book
            .including(required: Book.author
                .including(optional: Author.country)
                .forKey(CodingKeys.authorInfo))       // (1)
            .including(optional: Bool.coverImage)
            .asRequest(of: BookInfo.self)             // (2)
    }
}

let bookInfos = try BookInfo.all().fetchAll(db) // [BookInfo]
```

1. The `forKey(_:)` method changes the default key of the Book.author association, so that the associated author and country can feed the `authorInfo` property.
2. The `asRequest(of:)` method turns the request into a request of BookInfo. See [Custom Requests] for more information.


### Debugging Joined Request Decoding

When you have difficulties building a Decodable record that successfully decodes a joined request, we advise to temporarily add an `init(row:)` initializer to your record.

From this initializer, you can inspect each fetched row, and adapt your type accordingly:

```swift
struct BookInfo: FetchableRecord, Decodable {
    init(row: Row) {
        print(row.debugDescription)
    }
}

let bookInfos = try BookInfo.all().fetchAll(db) // [BookInfo]
// Prints:
// ▿ [id:1, authorId:2, title:"Moby-Dick"]
//   unadapted: [id:1, authorId:2, title:"Moby-Dick", id:2, name:"Herman Melville", countryCode:"US", code:"US", name:"United States of America", id:42, imageId:1, path:"moby-dick.jpg"]
//   - author: [id:2, name:"Herman Melville", countryCode:"US"]
//     - country: [code:NULL, name:NULL]
//   - coverImage: [id:NULL, imageId:NULL, path:NULL]
```

From the row debugging description, you can see that the fetched row contains book columns, and tree association keys: "author", "country", and "coverImage". The "country" and "coverImage" contains only null values, meaning that they are better decoded in optional properties:

```swift
struct BookInfo: FetchableRecord, Decodable {
    var book: Book              // decoded from the fetched row
    var author: Author          // decoded from the "author" key
    var country: Country?       // decoded from the "country" key
    var coverImage: CoverImage? // decoded from the "coverImage" key
}
```


## Decoding a Joined Request with FetchableRecord

When [Dedocable](#decoding-a-joined-request-with-a-decodable-record) records provides convenient decoding of joined rows, you may want a little more control over row decoding.

The `init(row:)` initializer of the FetchableRecord protocol is what you look after:

```swift
struct BookInfo: FetchableRecord, Decodable {
    var book: Book
    var author: Author
    var country: Country?
    var coverImage: CoverImage?
    
    init(row: Row) {
        book = Book(row: row)
        author = row["author"]
        country = row["country"]
        coverImage = row["coverImage"]
    }
}

let bookInfos = try BookInfo.fetchAll(db, request) // [BookInfo]
```

You are already familiar with row subscripts to decode [database values](https://github.com/groue/GRDB.swift/blob/GRDB3-Associations/README.md#column-values):

```swift
let name: String = row["name"]
```

When you extract a record instead of a value from a row, GRDB perfoms a breadth-first search in the tree of association keys defined by the joined request. If the key is not found, or only associated with columns that all contain NULL values, an optional record is decoded as nil:

```swift
let author: Author = row["author"]
let country: Country? = row["country"]
```

You can also perform custom navigation in the tree by using *row scopes*. See [Row Adapters] for more information.


## Future Directions

The APIs that have been described above do not cover the whole topic of joined requests. Among the biggest omissions, there is:

- One can not yet join two tables without a foreign key. One can not build the plain `SELECT * FROM a JOIN b`, for example.

- A common use case of associations is aggregations, such as fetching all authors with the number of books they have written:
    
    ```swift
    let request = Author.annotate(with: Author.books.count)
    ```
    
Those features are not present yet because they hide several very tough challenges. Come [discuss](http://twitter.com/groue) for more information, or if you wish to help turning those features into reality.


---

This documentation owns a lot to the [Active Record Associations](http://guides.rubyonrails.org/association_basics.html) guide, which is an immensely well-written introduction to database relations. Many thanks to the Rails team and contributors.

---

### LICENSE

**GRDB**

Copyright (C) 2018 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

**Ruby on Rails documentation**

Copyright (c) 2005-2018 David Heinemeier Hansson

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

[Associations Benefits]: #associations-benefits
[BelongsTo]: #belongsto
[HasOne]: #hasone
[HasMany]: #hasmany
[Choosing Between BelongsTo and HasOne]: #choosing-between-belongsto-and-hasone
[Self Joins]: #self-joins
[The Types of Associations]: #the-types-of-associations
[Codable]: https://developer.apple.com/documentation/swift/codable
[FetchableRecord]: https://github.com/groue/GRDB.swift/blob/GRDB3-Associations/README.md#fetchablerecord-protocols
[migration]: https://github.com/groue/GRDB.swift/blob/GRDB3-Associations/README.md#migrations
[Record]: https://github.com/groue/GRDB.swift/blob/GRDB3-Associations/README.md#records
[Foreign Key Actions]: https://sqlite.org/foreignkeys.html#fk_actions
[Associations and the Database Schema]: #associations-and-the-database-schema
[Convention for Database Table Names]: #convention-for-database-table-names
[Convention for the BelongsTo Association]: #convention-for-the-belongsto-association
[Convention for the HasOne Association]: #convention-for-the-hasone-association
[Convention for the HasMany Association]: #convention-for-the-hasmany-association
[Foreign Keys]: #foreign-keys
[Building Requests from Associations]: #building-requests-from-associations
[Fetching Values from Associations]: #fetching-values-from-associations
[Combining Associations]: #combining-associations
[Requesting Associated Records]: #requesting-associated-records
[Joining Methods]: #joining-methods
[Filtering Associations]: #filtering-associations
[Sorting Associations]: #sorting-associations
[Table Aliases]: #table-aliases
[The Structure of a Joined Request]: #the-structure-of-a-joined-request
[Decoding a Joined Request with a Decodable Record]: #decoding-a-joined-request-with-a-decodable-record
[Decoding a Joined Request with FetchableRecord]: #decoding-a-joined-request-with-fetchablerecord
[Custom Requests]: https://github.com/groue/GRDB.swift/blob/GRDB3-Associations/README.md#custom-requests
[Future Directions]: #future-directions
[Row Adapters]: https://github.com/groue/GRDB.swift/blob/GRDB3-Associations/README.md#row-adapters