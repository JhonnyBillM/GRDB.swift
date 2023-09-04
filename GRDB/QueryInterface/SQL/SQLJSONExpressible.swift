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
    ///     """.sqlJSON
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
    ///     """.sqlJSON
    /// let value = expression["$.a"]
    /// let string = try SQLRequest<String>("SELECT \(expression)").fetchOne(db)
    /// // Prints "xyz" (quotes included)
    /// print(string)
    /// ```
    subscript(_ path: some SQLExpressible) -> SQLJSON { get }
    
    /// Returns an SQL string, integer, double, NULL, or a JSON
    /// representation of the selected subcomponent(s), extracted with the
    /// `JSON_EXTRACT` SQL function.
    func extract(_ paths: [any SQLExpressible]) -> SQLExpression
}

extension SQLJSONExpressible {
    public var sqlExpression: SQLExpression {
        sqlJSON.sqlExpression
    }
    
    public var count: SQLExpression {
        sqlJSON.count
    }
    
    public subscript(valueAtPath path: some SQLExpressible) -> SQLExpression {
        sqlJSON[valueAtPath: path]
    }
    
    public subscript(_ path: some SQLExpressible) -> SQLJSON {
        sqlJSON[path]
    }
    
    public func extract(_ paths: [any SQLExpressible]) -> SQLExpression {
        sqlJSON.extract(paths)
    }
}

// MARK: - JSONColumn

/// A column in a database table that is parsed as JSON.
///
/// The JSON fetched by this column is always parsed and minified by SQLite,
/// with the `JSON` SQL function.
///
/// Related SQLite documentation <https://www.sqlite.org/json1.html#the_json_function>
public struct JSONColumn {
    public var name: String
    
    /// Returns a raw ``Column`` that is not parsed by SQLite.
    public var unparsedColumn: Column {
        Column(name)
    }
    
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
    public var sqlJSON: SQLJSON {
        .unparsed(.column(name))
    }
}

// MARK: - SQLJSON

public struct SQLJSON {
    private enum Impl {
        /// A JSON object that comes directly from the result of another
        /// JSON function or from the `->` operator (but not the
        /// `->>` operator, and is understood to be actual JSON.
        case jsonObject(SQLExpression)
        
        /// An expression that may not be understood as an actual JSON object.
        case unparsed(SQLExpression)
    }
    
    private var impl: Impl
    
    var unparsedJSON: SQLExpression {
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
    
    func qualified(with alias: TableAlias) -> SQLJSON {
        switch impl {
        case .jsonObject(let expression):
            return .jsonObject(expression.qualified(with: alias))
        case .unparsed(let expression):
            return .unparsed(expression.qualified(with: alias))
        }
    }
}

extension SQLJSON: SQLExpressible {
    public var sqlExpression: SQLExpression {
        switch impl {
        case .jsonObject(let expression):
            return expression
        case .unparsed(let expression):
            return .function("JSON", [expression])
        }
    }
}

extension SQLJSON: SQLJSONExpressible {
    // Not a real deprecation, just a usage warning
    @available(*, deprecated, message: "Already SQLJSON")
    public var sqlJSON: SQLJSON {
        self
    }
    
    public var count: SQLExpression {
        .function("JSON_ARRAY_LENGTH", [unparsedJSON])
    }
    
    // SQLite 3.38.0
    public subscript(valueAtPath path: some SQLExpressible) -> SQLExpression {
        .binary(.jsonSubcomponentValue, unparsedJSON, path.sqlExpression)
    }
    
    // SQLite 3.38.0
    public subscript(_ path: some SQLExpressible) -> SQLJSON {
        .jsonObject(.binary(.jsonSubcomponent, unparsedJSON, path.sqlExpression))
    }
    
    public func extract(_ paths: [any SQLExpressible]) -> SQLExpression {
        .function("JSON_EXTRACT", [unparsedJSON] + paths.map(\.sqlExpression))
    }
}

// MARK: - SQLExpressible Extension

extension SQLExpressible {
    public var sqlJSON: SQLJSON {
        .unparsed(sqlExpression)
    }
}

extension Collection<any SQLExpressible> {
    public var sqlJSON: SQLJSON {
        .jsonObject(.function("JSON_ARRAY", map(\.sqlExpression)))
    }
}

extension Collection where Element: SQLExpressible {
    public var sqlJSON: SQLJSON {
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
