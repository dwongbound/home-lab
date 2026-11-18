import XCTest
@testable import JarvisKit

final class ChatPhotosTests: XCTestCase {
    func testShrinksTheLongSideAndNeverEnlarges() {
        let big = PhotoLimits.scaled(width: 4032, height: 3024)
        XCTAssertEqual(big.width, 1600)
        XCTAssertEqual(big.height, 1200)
        let tall = PhotoLimits.scaled(width: 3024, height: 4032)
        XCTAssertEqual(tall.height, 1600)
        let small = PhotoLimits.scaled(width: 800, height: 600)
        XCTAssertEqual(small.width, 800)
    }

    func testQualityStepsDownThenStops() {
        XCTAssertEqual(PhotoLimits.lowerQuality(after: 0.8), 0.65)
        XCTAssertEqual(PhotoLimits.lowerQuality(after: 0.35), nil)
        XCTAssertEqual(PhotoLimits.room(holding: 3), 1)
        XCTAssertEqual(PhotoLimits.room(holding: 6), 0)
        XCTAssertEqual(PhotoLimits.chip(1), "1 photo")
        XCTAssertEqual(PhotoLimits.chip(3), "3 photos")
    }

    func testChatRequestCarriesPhotosWithoutAPrefix() throws {
        let client = JarvisClient(base: URL(string: "https://jarvis.example.ts.net")!)
        let photo = ChatPhoto(jpeg: Data([0xFF, 0xD8, 0xFF]))
        let request = client.chatRequest("", photos: Array(repeating: photo, count: 6))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(body["text"] as? String, "")
        let images = try XCTUnwrap(body["images"] as? [[String: String]])
        XCTAssertEqual(images.count, PhotoLimits.maxPhotos)
        XCTAssertEqual(images[0]["media_type"], "image/jpeg")
        XCTAssertEqual(images[0]["data"], "/9j/")
        XCTAssertFalse(images[0]["data"]!.hasPrefix("data:"))
        let plain = client.chatRequest("hi")
        let plainBody = try XCTUnwrap(JSONSerialization.jsonObject(with: plain.httpBody ?? Data()) as? [String: Any])
        XCTAssertNil(plainBody["images"])
    }

    func testHistoryTurnsCarryAPhotoCount() throws {
        let turn = try JSONDecoder().decode(ChatTurn.self, from: Data(#"{"role":"user","text":"","at":"x","images":2}"#.utf8))
        XCTAssertEqual(turn.images, 2)
        let old = try JSONDecoder().decode(ChatTurn.self, from: Data(#"{"role":"user","text":"hi","at":"x"}"#.utf8))
        XCTAssertNil(old.images)
    }
}

final class MealQuestionTests: XCTestCase {
    func testParsesTheMealQuestion() {
        let event = ChatEvent.parse(line: #"{"type":"meal_question","key":"m1","choices":["same","leftovers","new"]}"#)
        XCTAssertEqual(event, .mealQuestion(key: "m1", choices: ["same", "leftovers", "new"]))
        XCTAssertEqual(ChatEvent.parse(line: #"{"type":"meal_question","key":"m2","choices":["same","bogus"]}"#), .mealQuestion(key: "m2", choices: ["same"]))
        XCTAssertNil(ChatEvent.parse(line: #"{"type":"meal_question"}"#))
        XCTAssertEqual(MealChoice.label("leftovers"), "Leftovers")
        XCTAssertEqual(MealChoice.label("same"), "Same meal")
    }

    func testMealRequestShape() throws {
        let client = JarvisClient(base: URL(string: "https://jarvis.example.ts.net")!)
        let r = client.mealRequest(key: "m1", choice: "new")
        XCTAssertEqual(r.url?.path, "/api/jarvis/chat/meal")
        XCTAssertEqual(r.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: r.httpBody ?? Data()) as? [String: String]
        XCTAssertEqual(body, ["key": "m1", "choice": "new"])
    }

    func testCacheKeyIsStable() {
        XCTAssertEqual(PhotoCacheKey.key(text: "lunch", count: 2), PhotoCacheKey.key(text: "lunch", count: 2))
        XCTAssertNotEqual(PhotoCacheKey.key(text: "lunch", count: 2), PhotoCacheKey.key(text: "lunch", count: 1))
    }
}
