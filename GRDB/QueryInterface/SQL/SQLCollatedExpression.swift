/// SQLCollatedExpression taints an expression so that every derived expression
/// is eventually evaluated using an SQLite collation.
///
/// You create one by calling the `collating()` method:
///
///     let email = Column("email").collating(.nocase)
///
///     // SELECT * FROM player WHERE email = 'arthur@example.com' COLLATE NOCASE
///     Player.filter(email == "arthur@example.com")
public struct SQLCollatedExpression {
    /// The tainted expression
    public let expression: SQLExpression
    
    /// The name of the collation
    public let collationName: Database.CollationName
    
    /// Returns an ordering suitable for QueryInterfaceRequest.order()
    ///
    ///     let email: SQLCollatedExpression = Column("email").collating(.nocase)
    ///
    ///     // SELECT * FROM player ORDER BY email COLLATE NOCASE ASC
    ///     Player.order(email.asc)
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    public var asc: SQLOrderingTerm {
        _SQLOrdering.asc(sqlExpression)
    }
    
    /// Returns an ordering suitable for QueryInterfaceRequest.order()
    ///
    ///     let email: SQLCollatedExpression = Column("email").collating(.nocase)
    ///
    ///     // SELECT * FROM player ORDER BY email COLLATE NOCASE DESC
    ///     Player.order(email.desc)
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    public var desc: SQLOrderingTerm {
        _SQLOrdering.desc(sqlExpression)
    }
    
    #if GRDBCUSTOMSQLITE
    /// Returns an ordering suitable for QueryInterfaceRequest.order()
    ///
    ///     let email: SQLCollatedExpression = Column("email").collating(.nocase)
    ///
    ///     // SELECT * FROM player ORDER BY email COLLATE NOCASE ASC NULLS LAST
    ///     Player.order(email.ascNullsLast)
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    public var ascNullsLast: SQLOrderingTerm {
        _SQLOrdering.ascNullsLast(sqlExpression)
    }
    
    /// Returns an ordering suitable for QueryInterfaceRequest.order()
    ///
    ///     let email: SQLCollatedExpression = Column("email").collating(.nocase)
    ///
    ///     // SELECT * FROM player ORDER BY email COLLATE NOCASE DESC NULLS FIRST
    ///     Player.order(email.descNullsFirst)
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    public var descNullsFirst: SQLOrderingTerm {
        _SQLOrdering.descNullsFirst(sqlExpression)
    }
    #endif
    
    init(_ expression: SQLExpression, collationName: Database.CollationName) {
        self.expression = expression
        self.collationName = collationName
    }
    
    var sqlExpression: SQLExpression {
        _SQLExpressionCollate(expression, collationName: collationName)
    }
}

/// :nodoc:
extension SQLCollatedExpression: SQLOrderingTerm {
    /// :nodoc:
    public var _reversed: SQLOrderingTerm {
        desc
    }
    
    /// :nodoc:
    public func _qualifiedOrdering(with alias: TableAlias) -> SQLOrderingTerm {
        SQLCollatedExpression(expression._qualifiedExpression(with: alias), collationName: collationName)
    }
    
    /// :nodoc:
    public func _accept<Visitor: _SQLOrderingTermVisitor>(_ visitor: inout Visitor) throws {
        try visitor.visit(self)
    }
}