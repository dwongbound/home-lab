import XCTest
@testable import JarvisKit

final class HomeGlanceTests: XCTestCase {
    private func home(_ json: String) throws -> Home {
        try JSONDecoder().decode(Home.self, from: Data(json.utf8))
    }

    func testDecodesReadingsAndFullerWeather() throws {
        let h = try home("""
        {"devices":[],"weather":{"condition":"sunny","temperature":61,"unit":"°F","humidity":40,"wind":6,"windUnit":"mph"},
         "readings":[{"id":"binary_sensor.front","name":"Front door","kind":"door","value":"open"},
                     {"id":"sensor.bed_temp","name":"Bedroom","kind":"temperature","value":"70.5","unit":"°F"}]}
        """)
        XCTAssertEqual(h.readings?.count, 2)
        XCTAssertEqual(h.readings?[1].unit, "°F")
        XCTAssertEqual(h.weather?.humidity, 40)
        XCTAssertEqual(HomeGlance.weatherExtra(h.weather), "40% humidity · wind 6 mph")
    }

    func testOlderServerWithoutReadingsStillDecodes() throws {
        let h = try home(#"{"devices":[],"weather":{"condition":"cloudy","temperature":58,"unit":"°F"}}"#)
        XCTAssertNil(h.readings)
        XCTAssertNil(HomeGlance.weatherExtra(h.weather))
        XCTAssertEqual(HomeGlance.lines(h), [])
    }

    func testAttentionComesFirstAndQuietSensorsAreLeftOut() throws {
        let h = try home("""
        {"devices":[{"id":"t","name":"Thermostat","kind":"climate","state":"heat","detail":"heating","current":68,"target":70}],
         "readings":[{"id":"1","name":"Front door","kind":"door","value":"open"},
                     {"id":"2","name":"Back door","kind":"door","value":"closed"},
                     {"id":"3","name":"Hallway","kind":"motion","value":"detected"},
                     {"id":"4","name":"Porch sensor","kind":"battery","value":"12","unit":"%"},
                     {"id":"5","name":"Remote","kind":"battery","value":"80","unit":"%"}]}
        """)
        let lines = HomeGlance.lines(h)
        XCTAssertEqual(lines.map(\.title), ["Front door", "Hallway", "Porch sensor", "Thermostat"])
        XCTAssertEqual(lines.map(\.value), ["Open", "Motion", "Battery 12%", "68° · heating to 70°"])
        XCTAssertEqual(lines.prefix(3).map(\.attention), [true, true, true])
    }

    func testPlayingLightsAndRooms() throws {
        let h = try home("""
        {"devices":[{"id":"m","name":"Living Room TV","kind":"media","state":"playing","detail":"Netflix"},
                    {"id":"s","name":"Kitchen speaker","kind":"media","state":"idle"},
                    {"id":"a","name":"Desk","kind":"light","state":"on","brightness":0.6},
                    {"id":"b","name":"Hall","kind":"light","state":"off"}],
         "readings":[{"id":"1","name":"Bedroom","kind":"temperature","value":"70.5","unit":"°F"},
                     {"id":"2","name":"Bedroom","kind":"humidity","value":"44.6","unit":"%"}]}
        """)
        let lines = HomeGlance.lines(h)
        XCTAssertEqual(lines.map(\.title), ["Living Room TV", "Light on", "Bedroom"])
        XCTAssertEqual(lines.map(\.value), ["Netflix", "Desk", "71° · 45% humidity"])
        XCTAssertEqual(lines[0].symbol, "tv.fill")
    }

    func testManyLightsAreCountedNotNamed() throws {
        let lights = (1...5).map { #"{"id":"l\#($0)","name":"L\#($0)","kind":"light","state":"\#($0 <= 4 ? "on" : "off")"}"# }
        let h = try home(#"{"devices":[\#(lights.joined(separator: ","))]}"#)
        XCTAssertEqual(HomeGlance.lines(h).first?.value, "4 of 5 on")
    }

    func testNothingOnShowsNothing() throws {
        let h = try home(#"{"devices":[{"id":"b","name":"Hall","kind":"light","state":"off"},{"id":"s","name":"Speaker","kind":"media","state":"off"}]}"#)
        XCTAssertEqual(HomeGlance.lines(h), [])
    }
}
