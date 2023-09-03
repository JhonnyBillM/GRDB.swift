import XCTest
import GRDB

final class JSONFunctionTests: GRDBTestCase {
    
    private func assert<Output: DatabaseValueConvertible & Equatable>(
        _ db: Database,
        _ expression: SQLExpressible,
        equal expectedOutput: Output,
        file: StaticString = #file,
        line: UInt = #line) throws
    {
        let request: SQLRequest<Output> = "SELECT \(expression)"
        guard let json = try request.fetchOne(db) else {
            XCTFail(file: file, line: line)
            return
        }
        XCTAssertEqual(json, expectedOutput, file: file, line: line)
    }
    
    func test_JSON_function() throws {
        guard #available(iOS 16, macOS 13, tvOS 16, watchOS 9, *) else {
            throw XCTSkip("JSON functions are not available")
        }
        
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let expression = """
                 { "this" : "is", "a": [ "test" ] }
                """.sqlJSONExpression
            let value: String? = try SQLRequest("SELECT \(expression)").fetchOne(db)
            XCTAssertEqual(value, #"{"this":"is","a":["test"]}"#)
            XCTAssertEqual(lastSQLQuery, #"SELECT JSON(' { "this" : "is", "a": [ "test" ] }')"#)
        }
    }
    
    func test_JSON_ARRAY() throws {
        guard #available(iOS 16, macOS 13, tvOS 16, watchOS 9, *) else {
            throw XCTSkip("JSON functions are not available")
        }
        
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            do {
                let expression = (1...4).sqlJSONArray
                let value: String? = try SQLRequest("SELECT \(expression)").fetchOne(db)
                XCTAssertEqual(value, #"[1,2,3,4]"#)
                XCTAssertEqual(lastSQLQuery, #"SELECT JSON_ARRAY(1, 2, 3, 4)"#)
            }
            do {
                let expression = [
                    1.databaseValue,
                    2.databaseValue,
                    "3".databaseValue,
                    4.databaseValue,
                ].sqlJSONArray
                let value: String? = try SQLRequest("SELECT \(expression)").fetchOne(db)
                XCTAssertEqual(value, #"[1,2,"3",4]"#)
                XCTAssertEqual(lastSQLQuery, #"SELECT JSON_ARRAY(1, 2, '3', 4)"#)
            }
            do {
                let expression = [
                    [
                        1.databaseValue,
                        2.databaseValue,
                        "3".databaseValue,
                        4.databaseValue,
                    ].sqlJSONArray
                ].sqlJSONArray
                let value: String? = try SQLRequest("SELECT \(expression)").fetchOne(db)
                XCTAssertEqual(value, #"[[1,2,"3",4]]"#)
                XCTAssertEqual(lastSQLQuery, #"SELECT JSON_ARRAY(JSON_ARRAY(1, 2, '3', 4))"#)
            }
            do {
                let expression = [
                    1.databaseValue,
                    DatabaseValue.null,
                    "3".databaseValue,
                    "[4,5]".databaseValue,
                    "{\"six\":7.7}".databaseValue,
                ].sqlJSONArray
                let value: String? = try SQLRequest("SELECT \(expression)").fetchOne(db)
                XCTAssertEqual(value, #"[1,null,"3","[4,5]","{\"six\":7.7}"]"#)
                XCTAssertEqual(lastSQLQuery, #"SELECT JSON_ARRAY(1, NULL, '3', '[4,5]', '{"six":7.7}')"#)
            }
            do {
                let expression = [
                    1.databaseValue,
                    DatabaseValue.null,
                    "3".databaseValue,
                    "[4,5]".sqlJSONExpression,
                    "{\"six\":7.7}".sqlJSONExpression,
                ].sqlJSONArray
                let value: String? = try SQLRequest("SELECT \(expression)").fetchOne(db)
                XCTAssertEqual(value, #"[1,null,"3",[4,5],{"six":7.7}]"#)
                XCTAssertEqual(lastSQLQuery, #"SELECT JSON_ARRAY(1, NULL, '3', JSON('[4,5]'), JSON('{"six":7.7}'))"#)
            }
        }
    }
    
    func test_JSON_ARRAY_LENGTH() throws {
        guard #available(iOS 16, macOS 13, tvOS 16, watchOS 9, *) else {
            throw XCTSkip("JSON functions are not available")
        }
        
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            do {
                let expression = "[1,2,3,4]".sqlJSONExpression.count
                let value: Int? = try SQLRequest("SELECT \(expression)").fetchOne(db)
                XCTAssertEqual(value, 4)
                XCTAssertEqual(lastSQLQuery, #"SELECT JSON_ARRAY_LENGTH('[1,2,3,4]')"#)
            }
            try assert(db, "{\"one\":[1,2,3]}".sqlJSONExpression.count, equal: 0)
        }
    }
    
    func test_JSON_ARRAY_LENGTH_with_path() throws {
        guard #available(iOS 16, macOS 13, tvOS 16, watchOS 9, *) else {
            throw XCTSkip("JSON functions are not available")
        }
        
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            try assert(db, "[1,[2,3],4]".sqlJSONExpression[json: "$"].count, equal: 3)
            try assert(db, "[1,[2,3],4]".sqlJSONExpression[json: "$[1]"].count, equal: 2)
            try assert(db, "[1,[2,3],4]".sqlJSONExpression[json: "$[2]"].count, equal: 0)
        }
    }
    
    func test_JSONColumn() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            try db.create(table: "t") { $0.column("value") }
            try db.execute(sql: #"INSERT INTO t VALUES (' [1, {"foo" : "bar"}] ')"#)
            
            let table = Table("t")
            let column = Column("value")
            let jsonColumn = JSONColumn("value")
            
            do {
                // Test Column vs. JSONColumn when used as a result column.
                do {
                    let value = try table.select(column, as: String.self).fetchOne(db)
                    XCTAssertEqual(value, #" [1, {"foo" : "bar"}] "#)
                    XCTAssertEqual(lastSQLQuery, #"SELECT "value" FROM "t" LIMIT 1"#)
                }
                do {
                    // When JSONColumn is used as a result column, we don't perform any JSON validation.
                    let value = try table.select(jsonColumn, as: String.self).fetchOne(db)
                    XCTAssertEqual(value, #" [1, {"foo" : "bar"}] "#)
                    XCTAssertEqual(lastSQLQuery, #"SELECT "value" FROM "t" LIMIT 1"#)
                }
            }
            
            do {
                // Test Column vs. JSONColumn when used in SQL interpolation.
                do {
                    let value = try SQLRequest<String>("SELECT \(column) FROM \(table)").fetchOne(db)
                    XCTAssertEqual(value, #" [1, {"foo" : "bar"}] "#)
                    XCTAssertEqual(lastSQLQuery, #"SELECT "value" FROM "t""#)
                }
                do {
                    // This is questionable. But SQL interpolation favors
                    // expressions over result columns. Hence the json expression.
                    let value = try SQLRequest<String>("SELECT \(jsonColumn) FROM \(table)").fetchOne(db)
                    XCTAssertEqual(value, #"[1,{"foo":"bar"}]"#)
                    XCTAssertEqual(lastSQLQuery, #"SELECT JSON("value") FROM "t""#)
                }
            }
            
            do {
                // Test Column vs. JSONColumn when embedded in a JSON array.
                do {
                    // A Column is not interpreted as JSON.
                    let expression = [
                        0.databaseValue,
                        column
                    ].sqlJSONArray
                    let value = try table.select(expression, as: String.self).fetchOne(db)
                    XCTAssertEqual(value, #"[0," [1, {\"foo\" : \"bar\"}] "]"#)
                    XCTAssertEqual(lastSQLQuery, #"SELECT JSON_ARRAY(0, "value") FROM "t" LIMIT 1"#)
                }
                do {
                    // A JSONColumn is interpreted as JSON.
                    let expression = [
                        0.databaseValue,
                        jsonColumn
                    ].sqlJSONArray
                    let value = try table.select(expression, as: String.self).fetchOne(db)
                    XCTAssertEqual(value, #"[0,[1,{"foo":"bar"}]]"#)
                    XCTAssertEqual(lastSQLQuery, #"SELECT JSON_ARRAY(0, JSON("value")) FROM "t" LIMIT 1"#)
                }
            }
            
            do {
                // Test JSON value extraction
                do {
                    let expression = column.sqlJSONExpression[value: 0]
                    let value = try table.select(expression, as: Int.self).fetchOne(db)
                    XCTAssertEqual(value, 1)
                    XCTAssertEqual(lastSQLQuery, #"SELECT "value" ->> 0 FROM "t" LIMIT 1"#)
                }
                do {
                    let expression = jsonColumn[value: 0]
                    let value = try table.select(expression, as: Int.self).fetchOne(db)
                    XCTAssertEqual(value, 1)
                    XCTAssertEqual(lastSQLQuery, #"SELECT "value" ->> 0 FROM "t" LIMIT 1"#)
                }
            }
            
            do {
                // Test JSON extraction
                do {
                    let expression = column.sqlJSONExpression[json: 1]
                    let value = try table.select(expression, as: String.self).fetchOne(db)
                    XCTAssertEqual(value, #"{"foo":"bar"}"#)
                    XCTAssertEqual(lastSQLQuery, #"SELECT "value" -> 1 FROM "t" LIMIT 1"#)
                }
                do {
                    let expression = jsonColumn[json: 1]
                    let value = try table.select(expression, as: String.self).fetchOne(db)
                    XCTAssertEqual(value, #"{"foo":"bar"}"#)
                    XCTAssertEqual(lastSQLQuery, #"SELECT "value" -> 1 FROM "t" LIMIT 1"#)
                }
            }
            
            do {
                // Test deep JSON extraction
                do {
                    let expression = column.sqlJSONExpression[json: 1][json: "foo"]
                    let value = try table.select(expression, as: String.self).fetchOne(db)
                    XCTAssertEqual(value, #""bar""#)
                    XCTAssertEqual(lastSQLQuery, #"SELECT ("value" -> 1) -> 'foo' FROM "t" LIMIT 1"#)
                }
                do {
                    let expression = jsonColumn[json: 1][json: "foo"]
                    let value = try table.select(expression, as: String.self).fetchOne(db)
                    XCTAssertEqual(value, #""bar""#)
                    XCTAssertEqual(lastSQLQuery, #"SELECT ("value" -> 1) -> 'foo' FROM "t" LIMIT 1"#)
                }
            }
        }
    }
    
//    func testJSONExtract() throws {
//        guard #available(iOS 16, macOS 13, tvOS 16, watchOS 9, *) else {
//            throw XCTSkip("JSON functions are not available")
//        }
//        let dbQueue = try makeDatabaseQueue()
//
//        let input = """
//            {"a":2,"c":[4,5,{"f":7}]}
//            """.databaseValue
//
//        try dbQueue.inDatabase { db in
//            try assert(db, jsonExtract(input, "$"), equal: input)
//            try assert(db, jsonExtract(input, "$.c"), equal: "[4,5,{\"f\":7}]")
//            try assert(db, jsonExtract(input, "$.c[2]"), equal: "{\"f\":7}")
//            try assert(db, jsonExtract(input, "$.c[2].f"), equal: 7)
//            try assert(db, jsonExtract(input, "$.x"), equal: DatabaseValue.null)
//            try assert(db, jsonExtract(input, "$.x", "$.a"), equal: "[null,2]")
//        }
//    }
}
