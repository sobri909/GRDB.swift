public typealias AssociationMapping = (TableAlias, TableAlias) -> SQLExpressible?

enum AssociationMappingRequest {
    case foreignKey(request: ForeignKeyRequest, originIsLeft: Bool)
    
    func fetch(_ db: Database) throws -> AssociationMapping {
        switch self {
        case .foreignKey(request: let request, originIsLeft: let originIsLeft):
            let foreignKey = try request.fetch(db)
            let mapping: [(left: String, right: String)]
            if originIsLeft {
                mapping = foreignKey.mapping.map { (left: $0.origin, right: $0.destination) }
            } else {
                mapping = foreignKey.mapping.map { (left: $0.destination, right: $0.origin) }
            }
            return { (lhs, rhs) in
                let predicates = mapping.map { pair in
                    rhs[Column(pair.right)] == lhs[Column(pair.left)]
                }
                return SQLBinaryOperator.and.join(predicates)
            }
        }
    }
}
