typealias DatabasePromise<T> = (Database) throws -> T
typealias DatabaseTransform<T> = (Database, T) throws -> T
