/// JSON Schema for `TurnOutput`, sent as `output_config.format.schema`.
/// `resolution` is listed before `narration` so the model emits it first.
/// Keep optional branches rare: their combinations can exceed a provider's
/// compiled-grammar limit even when the JSON text itself is small.
import Foundation

public enum OutputSchema {
    /// The full turn grammar exceeds Claude's internal compilation limit even
    /// with all properties required. Only the resolution is transported as a
    /// JSON string; its complete typed contract is supplied in the prompt and
    /// decoded/validated locally before any state can be committed.
    public static let flatEnvelopeJSON = """
    {"type":"object","additionalProperties":false,"required":["resolution","narration","author_notes","choices"],"properties":{
      "resolution":{"type":"string","description":"A JSON-encoded object following the complete resolution contract in the prompt. This contains every proposed game-state change."},
      "narration":{"type":"string"},"author_notes":{"type":"string"},
      "choices":{"type":"array","items":{"type":"string"}}
    }}
    """

    static let flatEnvelopeInstructions = """
    Response transport: encode only the resolution object as a JSON string in the response's resolution field. Narration, author_notes and choices keep their normal types. Inside that string, include the complete resolution object defined by the logical JSON contract above, with all required arrays and exact field names. Use [] for unused systems and null for no crime. Do not encode the whole response as a string or put narration inside resolution. The engine parses and validates the inner object before saving anything.
    """

    private static var sourceTypes: String {
        // Recurring payments, transfers and asset proceeds are engine-owned.
        [SourceType.sideHustle, .gift, .inheritance, .windfall, .expense, .adjustment]
            .map { "\"\($0.rawValue)\"" }.joined(separator: ",")
    }

    private static let base: String = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["resolution", "narration", "author_notes", "choices"],
      "properties": {
        "resolution": {
          "type": "object",
          "additionalProperties": false,
          "required": ["zoom", "time_advance", "money", "income_streams", "decisions",
                       "life_state_changes", "cast_updates", "events"],
          "properties": {
            "zoom": { "type": "string", "enum": ["scene", "summary", "montage"] },
            "time_advance": {
              "type": "object",
              "additionalProperties": false,
              "required": ["unit", "amount"],
              "properties": {
                "unit": { "type": "string", "enum": ["days", "months", "years"] },
                "amount": { "type": "integer" }
              }
            },
            "money": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["source_type", "amount_minor", "reason", "account_id"],
                "properties": {
                  "source_type": { "type": "string", "enum": [\(sourceTypes)] },
                  "amount_minor": { "type": "integer" },
                  "reason": { "type": "string" },
                  "counterparty": { "type": "string" },
                  "account_id": { "type": "string", "description": "Exact destination/source account ID; use personal for personal funds." }
                }
              }
            },
            "income_streams": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["action", "name", "kind", "monthly_minor", "account_id", "effective_from", "reason"],
                "description": "For start/change provide the complete resulting rate, kind and destination. For end repeat the existing kind, rate and account; the engine ignores those values when closing the source.",
                "properties": {
                  "action": { "type": "string", "enum": ["start", "change", "end"] },
                  "name": { "type": "string" },
                  "kind": { "type": "string", "enum": ["wage", "self_employment", "business", "rental", "allowance"] },
                  "tier": { "type": "string" },
                  "monthly_minor": { "type": "integer", "description": "Net spendable recurring income in minor units per month; USD 50,000/month is 5000000, not a one-off gift or side hustle." },
                  "account_id": { "type": "string" },
                  "path_id": { "type": "string" },
                  "effective_from": { "type": "string", "description": "YYYY-MM-DD within this turn. Use turn end for a newly established rate, or turn start when the income operates throughout a time skip." },
                  "reason": { "type": "string" }
                }
              }
            },
            "decisions": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["summary", "choice", "importance"],
                "properties": {
                  "summary": { "type": "string" },
                  "choice": { "type": "string" },
                  "importance": { "type": "string", "enum": ["major", "minor"] }
                }
              }
            },
            "life_state_changes": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["key", "value"],
                "properties": {
                  "key": { "type": "string" },
                  "value": { "type": "string" }
                }
              }
            },
            "cast_updates": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["name"],
                "properties": {
                  "name": { "type": "string" },
                  "relation": { "type": "string" },
                  "notes": { "type": "string" },
                  "status": { "type": "string" }
                }
              }
            },
            "events": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["title", "importance", "uncanny"],
                "properties": {
                  "title": { "type": "string" },
                  "importance": { "type": "string", "enum": ["major", "minor"] },
                  "uncanny": { "type": "boolean" }
                }
              }
            }
          }
        },
        "narration": { "type": "string" },
        "author_notes": { "type": "string", "description": "Concise continuity notes, or an empty string." },
        "choices": { "type": "array", "description": "Optional next actions; use an empty array when there are none.", "items": { "type": "string" } }
      }
    }
    """
}


extension OutputSchema {
    public static var json: String {
        // These schemas are defined locally, not parsed from model output.
        let root = try! JSONSerialization.jsonObject(with: Data(base.utf8)) as! [String: Any]
        var properties = root["properties"] as! [String: Any]
        var resolution = properties["resolution"] as! [String: Any]
        var fields = resolution["properties"] as! [String: Any]
        func string(_ values: [String]? = nil) -> [String: Any] {
            var s: [String: Any] = ["type": "string"]
            if let values { s["enum"] = values }; return s
        }
        func array(_ fields: [String: Any]) -> [String: Any] {
            ["type": "array", "items": ["type": "object", "additionalProperties": false,
             "required": fields.keys.sorted(), "properties": fields]]
        }
        fields["path_updates"] = array(["id": string(), "title": string(), "stage": string(OpportunityPath.Stage.allCases.map(\.rawValue)), "notes": string()])
        fields["thread_updates"] = array(["id": string(), "title": string(), "notes": string(), "resolved": ["type": "boolean"]])
        fields["financial_actions"] = array(["action": string(["buy_asset", "sell_asset", "invest", "withdraw", "borrow", "repay"]),
            "id": string(), "name": string(), "amount_minor": ["type": "integer"], "account_id": string()])
        fields["account_openings"] = array(["id": string(), "name": string(), "kind": string(["personal", "business", "savings"])])
        fields["transfers"] = array(["from_account": string(), "to_account": string(), "amount_minor": ["type": "integer"], "reason": string()])
        fields["life_ended"] = ["type": "boolean", "description": "False while the protagonist is alive."]
        fields["crime_attempt"] = ["type": ["object", "null"], "additionalProperties": false,
            "description": "Omit or use null unless the protagonist actually attempts a crime in this scene. Ordinary actions, such as opening university letters, are not crimes.",
            "required": ["reason"], "properties": ["reason": ["type": "string", "description": "A concise cause of the actual offense, at most 500 characters; no operational methods."]]]
        // Empty arrays and false have unambiguous no-op semantics. Require them
        // instead of creating a branch for every unused feature. Crime remains
        // optional and nullable; cast patches retain omission = preserve semantics.
        resolution["required"] = fields.keys.filter { $0 != "crime_attempt" }.sorted()
        resolution["properties"] = fields; properties["resolution"] = resolution
        let ordered: String = ["resolution", "narration", "author_notes", "choices"].map { key -> String in
            let value = String(decoding: try! JSONSerialization.data(withJSONObject: properties[key]!, options: [.sortedKeys]), as: UTF8.self)
            return "\"\(key)\":\(value)"
        }.joined(separator: ",")
        return "{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"resolution\",\"narration\",\"author_notes\",\"choices\"],\"properties\":{\(ordered)}}"
    }
}
