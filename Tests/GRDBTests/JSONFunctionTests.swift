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
                """.sqlJSON
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
                let expression = (1...4).sqlJSON
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
                ].sqlJSON
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
                    ].sqlJSON
                ].sqlJSON
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
                ].sqlJSON
                let value: String? = try SQLRequest("SELECT \(expression)").fetchOne(db)
                XCTAssertEqual(value, #"[1,null,"3","[4,5]","{\"six\":7.7}"]"#)
                XCTAssertEqual(lastSQLQuery, #"SELECT JSON_ARRAY(1, NULL, '3', '[4,5]', '{"six":7.7}')"#)
            }
            do {
                let expression = [
                    1.databaseValue,
                    DatabaseValue.null,
                    "3".databaseValue,
                    "[4,5]".sqlJSON,
                    "{\"six\":7.7}".sqlJSON,
                ].sqlJSON
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
                let expression = "[1,2,3,4]".sqlJSON.count
                let value: Int? = try SQLRequest("SELECT \(expression)").fetchOne(db)
                XCTAssertEqual(value, 4)
                XCTAssertEqual(lastSQLQuery, #"SELECT JSON_ARRAY_LENGTH('[1,2,3,4]')"#)
            }
            try assert(db, "{\"one\":[1,2,3]}".sqlJSON.count, equal: 0)
        }
    }
    
    func test_JSON_ARRAY_LENGTH_with_path() throws {
        guard #available(iOS 16, macOS 13, tvOS 16, watchOS 9, *) else {
            throw XCTSkip("JSON functions are not available")
        }
        
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            try assert(db, "[1,[2,3],4]".sqlJSON[jsonAtPath: "$"].count, equal: 3)
            try assert(db, "[1,[2,3],4]".sqlJSON[jsonAtPath: "$[1]"].count, equal: 2)
            try assert(db, "[1,[2,3],4]".sqlJSON[jsonAtPath: "$[2]"].count, equal: 0)
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
                    let value = try table.select(jsonColumn, as: String.self).fetchOne(db)
                    XCTAssertEqual(value, #"[1,{"foo":"bar"}]"#)
                    XCTAssertEqual(lastSQLQuery, #"SELECT JSON("value") FROM "t" LIMIT 1"#)
                }
                do {
                    let value = try table.select(jsonColumn.unparsedColumn, as: String.self).fetchOne(db)
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
                    ].sqlJSON
                    let value = try table.select(expression, as: String.self).fetchOne(db)
                    XCTAssertEqual(value, #"[0," [1, {\"foo\" : \"bar\"}] "]"#)
                    XCTAssertEqual(lastSQLQuery, #"SELECT JSON_ARRAY(0, "value") FROM "t" LIMIT 1"#)
                }
                do {
                    // A JSONColumn is interpreted as JSON.
                    let expression = [
                        0.databaseValue,
                        jsonColumn
                    ].sqlJSON
                    let value = try table.select(expression, as: String.self).fetchOne(db)
                    XCTAssertEqual(value, #"[0,[1,{"foo":"bar"}]]"#)
                    XCTAssertEqual(lastSQLQuery, #"SELECT JSON_ARRAY(0, JSON("value")) FROM "t" LIMIT 1"#)
                }
            }
            
            do {
                // Test JSON value extraction
                do {
                    let expression = column.sqlJSON[0]
                    let value = try table.select(expression, as: Int.self).fetchOne(db)
                    XCTAssertEqual(value, 1)
                    XCTAssertEqual(lastSQLQuery, #"SELECT "value" ->> 0 FROM "t" LIMIT 1"#)
                }
                do {
                    let expression = jsonColumn[0]
                    let value = try table.select(expression, as: Int.self).fetchOne(db)
                    XCTAssertEqual(value, 1)
                    XCTAssertEqual(lastSQLQuery, #"SELECT "value" ->> 0 FROM "t" LIMIT 1"#)
                }
            }
            
            do {
                // Test JSON extraction
                do {
                    let expression = column.sqlJSON[jsonAtPath: 1]
                    let value = try table.select(expression, as: String.self).fetchOne(db)
                    XCTAssertEqual(value, #"{"foo":"bar"}"#)
                    XCTAssertEqual(lastSQLQuery, #"SELECT "value" -> 1 FROM "t" LIMIT 1"#)
                }
                do {
                    let expression = jsonColumn[jsonAtPath: 1]
                    let value = try table.select(expression, as: String.self).fetchOne(db)
                    XCTAssertEqual(value, #"{"foo":"bar"}"#)
                    XCTAssertEqual(lastSQLQuery, #"SELECT "value" -> 1 FROM "t" LIMIT 1"#)
                }
            }
            
            do {
                // Test deep JSON extraction
                do {
                    let expression = column.sqlJSON[jsonAtPath: 1][jsonAtPath: "foo"]
                    let value = try table.select(expression, as: String.self).fetchOne(db)
                    XCTAssertEqual(value, #""bar""#)
                    XCTAssertEqual(lastSQLQuery, #"SELECT ("value" -> 1) -> 'foo' FROM "t" LIMIT 1"#)
                }
                do {
                    let expression = jsonColumn[jsonAtPath: 1][jsonAtPath: "foo"]
                    let value = try table.select(expression, as: String.self).fetchOne(db)
                    XCTAssertEqual(value, #""bar""#)
                    XCTAssertEqual(lastSQLQuery, #"SELECT ("value" -> 1) -> 'foo' FROM "t" LIMIT 1"#)
                }
            }
            
            do {
                // Test count
                do {
                    let expression = column.sqlJSON.count
                    let value = try table.select(expression, as: Int.self).fetchOne(db)
                    XCTAssertEqual(value, 2)
                    XCTAssertEqual(lastSQLQuery, #"SELECT JSON_ARRAY_LENGTH("value") FROM "t" LIMIT 1"#)
                }
                do {
                    let expression = jsonColumn.count
                    let value = try table.select(expression, as: Int.self).fetchOne(db)
                    XCTAssertEqual(value, 2)
                    XCTAssertEqual(lastSQLQuery, #"SELECT JSON_ARRAY_LENGTH("value") FROM "t" LIMIT 1"#)
                }
            }
        }
    }
    
    func testOperators() throws {
        try makeDatabaseQueue().inDatabase { db in
            let expression = #"["[1, 2, 3]"]"#.sqlJSON
            do {
                let value: String? = try SQLRequest("SELECT \(expression[jsonAtPath: 0])").fetchOne(db)
                XCTAssertEqual(value, #""[1, 2, 3]""#)
                XCTAssertEqual(lastSQLQuery, #"SELECT '["[1, 2, 3]"]' -> 0"#)
            }
            do {
                let value: String? = try SQLRequest("SELECT \(expression[jsonAtPath: 0][jsonAtPath: 0])").fetchOne(db)
                XCTAssertNil(value)
                XCTAssertEqual(lastSQLQuery, #"SELECT ('["[1, 2, 3]"]' -> 0) -> 0"#)
            }
            do {
                let value: Int? = try SQLRequest("SELECT \(expression[0].sqlJSON[jsonAtPath: 0])").fetchOne(db)
                XCTAssertEqual(value, 1)
                XCTAssertEqual(lastSQLQuery, #"SELECT ('["[1, 2, 3]"]' ->> 0) -> 0"#)
            }
        }
    }
    
    func test_JSON_EXTRACT() throws {
        guard #available(iOS 16, macOS 13, tvOS 16, watchOS 9, *) else {
            throw XCTSkip("JSON functions are not available")
        }
        let dbQueue = try makeDatabaseQueue()

        let input = """
            {"a":2,"c":[4,5,{"f":7}]}
            """

        try dbQueue.inDatabase { db in
            try assert(db, input.sqlJSON.extract(["$"]), equal: input)
            try assert(db, input.sqlJSON.extract(["$.c"]), equal: "[4,5,{\"f\":7}]")
            try assert(db, input.sqlJSON.extract(["$.c[2]"]), equal: "{\"f\":7}")
            try assert(db, input.sqlJSON.extract(["$.c[2].f"]), equal: 7)
            try assert(db, input.sqlJSON.extract(["$.x"]), equal: DatabaseValue.null)
            try assert(db, input.sqlJSON.extract(["$.x", "$.a"]), equal: "[null,2]")
        }
    }
    
    func test_index_on_json_key() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            try db.create(table: "test") { t in
                t.column("json", .jsonText).check { $0.isValidJSON }
            }
            XCTAssertEqual(lastSQLQuery, """
                CREATE TABLE "test" ("json" TEXT CHECK (JSON_VALID("json")))
                """)
            try db.create(index: "index_test", on: "test", expressions: [JSONColumn("json")["name"]])
            XCTAssertEqual(lastSQLQuery, """
                CREATE INDEX "index_test" ON "test"("json" ->> 'name')
                """)
        }
    }
}
