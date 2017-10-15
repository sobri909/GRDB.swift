public struct HasOneOptionalAssociation<Left, Right> : Association, AssociationToOne where
    Left: TableMapping,
    Right: TableMapping
{
    // Association
    public typealias LeftAssociated = Left
    public typealias RightAssociated = Right

    let joinMappingRequest: JoinMappingRequest
    public let rightRequest: WrappedRequest
    
    public func mapping(_ db: Database) throws -> [(left: String, right: String)] {
        return try joinMappingRequest
            .fetchMapping(db)
            .map { (left: $0.destination, right: $0.origin) }
    }
}

extension HasOneOptionalAssociation : RequestDerivableWrapper {
    public typealias WrappedRequest = QueryInterfaceRequest<Right>
    
    public func mapRequest(_ transform: (WrappedRequest) -> WrappedRequest) -> HasOneOptionalAssociation {
        return HasOneOptionalAssociation(
            joinMappingRequest: joinMappingRequest,
            rightRequest: transform(self.rightRequest))
    }
}

extension TableMapping {
    public static func hasOne<Right>(
        optional right: Right.Type,
        using foreignKey: ForeignKey? = nil)
        -> HasOneOptionalAssociation<Self, Right>
        where Right: TableMapping
    {
        let joinMappingRequest = JoinMappingRequest(
            originTable: Right.databaseTableName,
            destinationTable: databaseTableName,
            foreignKey: foreignKey)
        return HasOneOptionalAssociation(joinMappingRequest: joinMappingRequest, rightRequest: Right.all())
    }
}
