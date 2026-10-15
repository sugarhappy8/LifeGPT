import Foundation
import Testing
@testable import LifeCore

@Suite struct ContractTests {
    static let sample = """
    {
      "resolution": {
        "zoom": "summary",
        "time_advance": { "unit": "months", "amount": 2 },
        "money": [
          { "source_type": "side_hustle", "amount_minor": 8500,
            "reason": "sold six hand-carved spoons at the Saturday market",
            "income_stream": "spoon-stall", "fate_used": 61 }
        ],
        "income_streams": [
          { "action": "start", "name": "hardware store", "kind": "wage", "tier": "entry", "monthly_minor": 200000 }
        ],
        "decisions": [ { "summary": "Took a job", "choice": "hardware store", "importance": "major" } ],
        "life_state_changes": [ { "key": "occupation", "value": "clerk" } ],
        "cast_updates": [ { "name": "Maria", "relation": "mother", "notes": "proud" } ],
        "events": [ { "title": "First day", "importance": "minor", "uncanny": false } ]
      },
      "narration": "You tie on the apron.",
      "author_notes": "Maria worries about money.",
      "choices": ["Ask about overtime", "Go home"]
    }
    """

    static func decode(_ json: String) throws -> TurnOutput {
        try OutputCoding.decoder.decode(TurnOutput.self, from: Data(json.utf8))
    }

    @Test func decodesFullOutput() throws {
        let out = try Self.decode(Self.sample)
        #expect(out.resolution.zoom == .summary)
        #expect(out.resolution.timeAdvance == TimeAdvance(unit: .months, amount: 2))
        #expect(out.resolution.money[0].sourceType == .sideHustle)
        #expect(out.resolution.money[0].amountMinor == 8_500)
        #expect(out.resolution.money[0].incomeStream == "spoon-stall")
        #expect(out.resolution.money[0].fateUsed == 61)
        #expect(out.resolution.incomeStreams[0].action == .start)
        #expect(out.resolution.incomeStreams[0].monthlyMinor == 200_000)
        #expect(out.resolution.decisions[0].importance == .major)
        #expect(out.resolution.lifeStateChanges == [LifeStateChange(key: "occupation", value: "clerk")])
        #expect(out.resolution.castUpdates[0].notes == "proud")
        #expect(out.resolution.events[0].uncanny == false)
        #expect(out.narration == "You tie on the apron.")
        #expect(out.choices == ["Ask about overtime", "Go home"])
    }

    @Test func unknownSourceTypeFailsToDecode() {
        let bad = Self.sample.replacingOccurrences(of: "side_hustle", with: "magic_beans")
        #expect(throws: DecodingError.self) { _ = try Self.decode(bad) }
    }

    @Test func missingResolutionFailsToDecode() {
        #expect(throws: DecodingError.self) { _ = try Self.decode(#"{ "narration": "Hi." }"#) }
    }

    @Test func encodingRoundTripsInSnakeCase() throws {
        let out = try Self.decode(Self.sample)
        let data = try OutputCoding.encoder.encode(out)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"time_advance\""))
        #expect(text.contains("\"amount_minor\""))
        #expect(try OutputCoding.decoder.decode(TurnOutput.self, from: data) == out)
    }

    @Test func schemaIsJSONWithRequiredKeys() throws {
        let schema = try #require(JSONSerialization.jsonObject(with: Data(OutputSchema.json.utf8)) as? [String: Any])
        #expect(schema["required"] as? [String] == ["resolution", "narration"])
        #expect(schema["additionalProperties"] as? Bool == false)
        let resolution = try #require((schema["properties"] as? [String: Any])?["resolution"] as? [String: Any])
        let required = try #require(resolution["required"] as? [String])
        #expect(Set(required).isSuperset(of: ["zoom", "time_advance", "money", "income_streams"]))
    }

    @Test func schemaListsResolutionBeforeNarration() throws {
        let r = try #require(OutputSchema.json.range(of: "\"resolution\":"))
        let n = try #require(OutputSchema.json.range(of: "\"narration\":"))
        #expect(r.lowerBound < n.lowerBound)
    }

    @Test func schemaSourceTypesMatchTheEnum() throws {
        let schema = try #require(JSONSerialization.jsonObject(with: Data(OutputSchema.json.utf8)) as? [String: Any])
        let resolution = try #require((schema["properties"] as? [String: Any])?["resolution"] as? [String: Any])
        let money = try #require((resolution["properties"] as? [String: Any])?["money"] as? [String: Any])
        let item = try #require(money["items"] as? [String: Any])
        let source = try #require((item["properties"] as? [String: Any])?["source_type"] as? [String: Any])
        #expect(Set(try #require(source["enum"] as? [String])) == Set(SourceType.allCases.map(\.rawValue)))
    }

    @Test func addingTimeAdvance() {
        let start = GameDate(year: 2020, month: 1, day: 31)
        #expect(start.adding(TimeAdvance(unit: .months, amount: 2)) == GameDate(year: 2020, month: 3, day: 31))
        #expect(start.adding(TimeAdvance(unit: .days, amount: 1)) == GameDate(year: 2020, month: 2, day: 1))
        #expect(start.adding(TimeAdvance(unit: .years, amount: 1)) == GameDate(year: 2021, month: 1, day: 31))
    }
}
