// SQLite 3.37.2 (opt-in) 3.38.0 (opt-out)
public protocol SQLJSONExpressible: SQLSpecificExpressible {
    var sqlJSONExpression: SQLJSONExpression { get }
    var count: SQLExpression { get }
}

extension SQLJSONExpressible {
    public var sqlOrdering: SQLOrdering {
        sqlJSONExpression.sqlOrdering
    }
    
    public var sqlSelection: SQLSelection {
        sqlJSONExpression.sqlSelection
    }
    
    public var sqlExpression: SQLExpression {
        sqlJSONExpression.sqlExpression
    }
}

extension SQLJSONExpressible {
    // SQLite 3.38.0
    public subscript(value path: SQLExpressible) -> SQLExpression {
        sqlJSONExpression.jsonSubcomponentValue(atPath: path)
    }
    
    // SQLite 3.38.0
    public subscript(json path: SQLExpressible) -> SQLJSONExpression {
        sqlJSONExpression.jsonSubcomponent(atPath: path)
    }
}

// MARK: - JSONColumn

/// A column in a database table that contains JSON.
public struct JSONColumn {
    public var name: String
    
    /// Creates a `Column` given its name.
    ///
    /// The name should be unqualified, such as `"score"`. Qualified name such
    /// as `"player.score"` are unsupported.
    public init(_ name: String) {
        self.name = name
    }
    
    /// Creates a `Column` given a `CodingKey`.
    public init(_ codingKey: some CodingKey) {
        self.name = codingKey.stringValue
    }
}

extension JSONColumn: SQLExpressible {
    public var sqlExpression: SQLExpression {
        // make sure we return a JSON object
        .function("JSON", [.column(name)])
    }
}

extension JSONColumn: ColumnExpression { }

extension JSONColumn: SQLJSONExpressible {
    public var sqlJSONExpression: SQLJSONExpression {
        .raw(.column(name))
    }
    
    public var count: SQLExpression {
        return .function("JSON_ARRAY_LENGTH", [.column(name)])
    }
}

// MARK: - SQLJSONExpression

public struct SQLJSONExpression {
    private enum Impl {
        /// A JSON object that comes directly from the result of another
        /// JSON function or from the `->` operator (but not the
        /// `->>` operator, and is understood to be actual JSON.
        case jsonObject(SQLExpression)
        
        /// An expression that may not be understood as an actual JSON object.
        case raw(SQLExpression)
    }
    private var impl: Impl
    
    private init(impl: Impl) {
        self.impl = impl
    }
    
    public var count: SQLExpression {
        switch impl {
        case .jsonObject(let expression),
             .raw(let expression):
            return .function("JSON_ARRAY_LENGTH", [expression])
        }
    }
    
    static func jsonObject(_ expression: SQLExpression) -> Self {
        .init(impl: .jsonObject(expression))
    }
    
    static func raw(_ expression: SQLExpression) -> Self {
        .init(impl: .raw(expression))
    }
    
    // SQLite 3.38.0
    func jsonSubcomponentValue(atPath path: SQLExpressible) -> SQLExpression {
        switch impl {
        case .jsonObject(let expression),
            .raw(let expression):
            return .binary(.jsonSubcomponentValue, expression, path.sqlExpression)
        }
    }
    
    // SQLite 3.38.0
    func jsonSubcomponent(atPath path: SQLExpressible) -> SQLJSONExpression {
        switch impl {
        case .jsonObject(let expression),
             .raw(let expression):
            return .jsonObject(.binary(.jsonSubcomponent, expression, path.sqlExpression))
        }
    }
    
    func qualified(with alias: TableAlias) -> SQLJSONExpression {
        switch impl {
        case .jsonObject(let expression):
            return .jsonObject(expression.qualified(with: alias))
        case .raw(let expression):
            return .raw(expression.qualified(with: alias))
        }
    }
}

extension SQLJSONExpression: SQLOrderingTerm {
    public var sqlOrdering: SQLOrdering {
        // Don't have SQLite parse JSON used for ordering
        switch impl {
        case .jsonObject(let expression),
                .raw(let expression):
            return .expression(expression)
        }
    }
}

extension SQLJSONExpression: SQLSelectable {
    public var sqlSelection: SQLSelection {
        // Don't have SQLite parse selected JSON
        switch impl {
        case .jsonObject(let expression),
                .raw(let expression):
            return .expression(expression)
        }
    }
}

extension SQLJSONExpression: SQLExpressible {
    public var sqlExpression: SQLExpression {
        // make sure we return a JSON object
        switch impl {
        case .jsonObject(let expression):
            return expression
        case .raw(let expression):
            return .function("JSON", [expression])
        }
    }
}

extension SQLJSONExpression: SQLJSONExpressible {
    public var sqlJSONExpression: SQLJSONExpression {
        self
    }
}

// MARK: - SQLExpressible Extension

extension SQLExpressible {
    // TODO: incorrect. This conflicts with SQLJSONExpressible.sqlJSONExpression.
    // sqlJSONExpression should be moved to SQLExpressible
    public var sqlJSONExpression: SQLJSONExpression {
        .raw(sqlExpression)
    }
}

extension Collection<any SQLExpressible> {
    public var sqlJSONArray: SQLJSONExpression {
        .jsonObject(.function("JSON_ARRAY", map(\.sqlExpression)))
    }
}

extension Collection where Element: SQLExpressible {
    public var sqlJSONArray: SQLJSONExpression {
        .jsonObject(.function("JSON_ARRAY", map(\.sqlExpression)))
    }
}

// MARK: - SQLSpecificExpressible Extension

extension SQLSpecificExpressible {
    public var isValidJSON: SQLExpression {
        .function("JSON_VALID", [sqlExpression])
    }
    
    // SQLite 3.42.0+
    public var isValidJSON5: SQLExpression {
        SQLExpression.function("JSON_ERROR_POSITION", [sqlExpression]) == 0
    }
}
