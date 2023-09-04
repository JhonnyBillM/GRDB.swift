// SQLite 3.37.2 (opt-in) 3.38.0 (opt-out)
/// A type that can be used as a JSON SQL expression.
///
/// See <doc:JSONExpressions>.
/// 
/// Related SQLite documentation <https://www.sqlite.org/json1.html>.
public protocol SQLJSONExpressible: SQLSpecificExpressible {
    /// Returns the number of elements in the JSON array, or 0 if the
    /// expression is some kind of JSON value other than an array, with the
    /// `JSON_ARRAY_LENGTH` SQL function.
    ///
    /// For example:
    ///
    /// ```swift
    /// let column = JSONColumn("awardsJSON")
    ///
    /// // SQL> SELECT JSON_ARRAY_LENGTH(awardsJSON) FROM player WHERE id = 1
    /// let awardCount = Player
    ///     .filter(id: 1)
    ///     .select(column.count, as: Int.self)
    ///     .fetchOne(db)
    /// ```
    ///
    /// Related SQLite documentation <https://www.sqlite.org/json1.html#the_json_array_length_function>
    var count: SQLExpression { get }
    
    /// Returns a minified version of that JSON expression (with all
    /// unnecessary whitespace removed).
    ///
    /// Use this property when you want SQLite to parse and minify JSON
    /// columns, for example. Compare:
    ///
    /// ```swift
    /// let column = JSONColumn("detailsJSON")
    ///
    /// // Not minified
    /// // SQL> SELECT detailsJSON FROM player WHERE id = 1
    /// let rawDetails = Player
    ///     .filter(id: 1)
    ///     .select(column, as: String.self)
    ///     .fetchOne(db)
    ///
    /// // Minified
    /// // SQL> SELECT JSON(detailsJSON) FROM player WHERE id = 1
    /// let rawDetails = Player
    ///     .filter(id: 1)
    ///     .select(column.minifiedJSON, as: String.self)
    ///     .fetchOne(db)
    /// ```
    var minifiedJSON: SQLJSONExpression { get }
    
    // SQLite 3.38.0
    /// Returns an SQL string, integer, double, or NULL value that
    /// represents the selected subcomponent, extracted with the `->>`
    /// SQL operator.
    ///
    /// For example:
    ///
    /// ```swift
    /// let expression = """
    ///     {"a":"xyz"}
    ///     """.sqlJSONExpression
    /// let value = expression[valueAtPath: "$.a"]
    /// let string = try SQLRequest<String>("SELECT \(expression)").fetchOne(db)
    /// // Prints "xyz" (quotes not included)
    /// print(string)
    /// ```
    subscript(valueAtPath path: some SQLExpressible) -> SQLExpression { get }
    
    // SQLite 3.38.0
    /// Returns a JSON representation of the selected subcomponent,
    /// extracted with the `->` SQL operator.
    ///
    /// For example:
    ///
    /// ```swift
    /// let expression = """
    ///     {"a":"xyz"}
    ///     """.sqlJSONExpression
    /// let value = expression["$.a"]
    /// let string = try SQLRequest<String>("SELECT \(expression)").fetchOne(db)
    /// // Prints "xyz" (quotes included)
    /// print(string)
    /// ```
    subscript(_ path: some SQLExpressible) -> SQLJSONExpression { get }
    
    /// Returns an SQL string, integer, double, NULL, or a JSON
    /// representation of the selected subcomponent(s), extracted with the
    /// `JSON_EXTRACT` SQL function.
    func extract(_ paths: [any SQLExpressible]) -> SQLExpression
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
    
    public var count: SQLExpression {
        sqlJSONExpression.count
    }
    
    public var minifiedJSON: SQLJSONExpression {
        sqlJSONExpression.minifiedJSON
    }
    
    public subscript(valueAtPath path: some SQLExpressible) -> SQLExpression {
        sqlJSONExpression[valueAtPath: path]
    }
    
    public subscript(_ path: some SQLExpressible) -> SQLJSONExpression {
        sqlJSONExpression[path]
    }
    
    public func extract(_ paths: [any SQLExpressible]) -> SQLExpression {
        sqlJSONExpression.extract(paths)
    }
}

// MARK: - JSONColumn

/// A column in a database table that contains JSON.
public struct JSONColumn {
    public var name: String
    
    /// Creates a `JSONColumn` given its name.
    ///
    /// The name should be unqualified, such as `"detailsJSON"`. Qualified
    /// name such as `"player.detailsJSON"` are unsupported.
    public init(_ name: String) {
        self.name = name
    }
    
    /// Creates a `JSONColumn` given a `CodingKey`.
    public init(_ codingKey: some CodingKey) {
        self.name = codingKey.stringValue
    }
}

extension JSONColumn: SQLExpressible {
    public var sqlExpression: SQLExpression {
        .function("JSON", [.column(name)])
    }
}

extension JSONColumn: ColumnExpression { }

extension JSONColumn: SQLJSONExpressible {
    public var sqlJSONExpression: SQLJSONExpression {
        .unparsed(.column(name))
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
        case unparsed(SQLExpression)
    }
    
    private var impl: Impl
    
    var unparsedExpression: SQLExpression {
        switch impl {
        case .jsonObject(let expression), .unparsed(let expression):
            return expression
        }
    }
    
    private init(impl: Impl) {
        self.impl = impl
    }
    
    static func jsonObject(_ expression: SQLExpression) -> Self {
        .init(impl: .jsonObject(expression))
    }
    
    static func unparsed(_ expression: SQLExpression) -> Self {
        .init(impl: .unparsed(expression))
    }
    
    func qualified(with alias: TableAlias) -> SQLJSONExpression {
        switch impl {
        case .jsonObject(let expression):
            return .jsonObject(expression.qualified(with: alias))
        case .unparsed(let expression):
            return .unparsed(expression.qualified(with: alias))
        }
    }
}

extension SQLJSONExpression: SQLOrderingTerm {
    public var sqlOrdering: SQLOrdering {
        // Don't have SQLite parse JSON used for ordering
        .expression(unparsedExpression)
    }
}

extension SQLJSONExpression: SQLSelectable {
    public var sqlSelection: SQLSelection {
        // Don't have SQLite parse selected JSON
        .expression(unparsedExpression)
    }
}

extension SQLJSONExpression: SQLExpressible {
    public var sqlExpression: SQLExpression {
        switch impl {
        case .jsonObject(let expression):
            return expression
        case .unparsed(let expression):
            return .function("JSON", [expression])
        }
    }
}

extension SQLJSONExpression: SQLJSONExpressible {
    // Not a real deprecation, just a usage warning
    @available(*, deprecated, message: "Already SQLJSONExpression")
    public var sqlJSONExpression: SQLJSONExpression {
        self
    }
    
    public var count: SQLExpression {
        .function("JSON_ARRAY_LENGTH", [unparsedExpression])
    }
    
    public var minifiedJSON: SQLJSONExpression {
        switch impl {
        case .jsonObject:
            return self
        case .unparsed(let expression):
            return .jsonObject(.function("JSON", [expression]))
        }
    }
    
    // SQLite 3.38.0
    public subscript(valueAtPath path: some SQLExpressible) -> SQLExpression {
        .binary(.jsonSubcomponentValue, unparsedExpression, path.sqlExpression)
    }
    
    // SQLite 3.38.0
    public subscript(_ path: some SQLExpressible) -> SQLJSONExpression {
        .jsonObject(.binary(.jsonSubcomponent, unparsedExpression, path.sqlExpression))
    }
    
    public func extract(_ paths: [any SQLExpressible]) -> SQLExpression {
        .function("JSON_EXTRACT", [unparsedExpression] + paths.map(\.sqlExpression))
    }
}

// MARK: - SQLExpressible Extension

extension SQLExpressible {
    public var sqlJSONExpression: SQLJSONExpression {
        .unparsed(sqlExpression)
    }
}

extension Collection<any SQLExpressible> {
    public var sqlJSONExpression: SQLJSONExpression {
        .jsonObject(.function("JSON_ARRAY", map(\.sqlExpression)))
    }
}

extension Collection where Element: SQLExpressible {
    public var sqlJSONExpression: SQLJSONExpression {
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
