/// JSON Schema for `TurnOutput`, sent as `output_config.format.schema`.
/// `resolution` is listed before `narration` so the model emits it first.
public enum OutputSchema {
    private static var sourceTypes: String {
        SourceType.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
    }

    public static let json: String = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["resolution", "narration"],
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
                "required": ["source_type", "amount_minor", "reason"],
                "properties": {
                  "source_type": { "type": "string", "enum": [\(sourceTypes)] },
                  "amount_minor": { "type": "integer" },
                  "reason": { "type": "string" },
                  "income_stream": { "type": "string" },
                  "counterparty": { "type": "string" },
                  "fate_used": { "type": "integer" }
                }
              }
            },
            "income_streams": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["action", "name"],
                "properties": {
                  "action": { "type": "string", "enum": ["start", "change", "end"] },
                  "name": { "type": "string" },
                  "kind": { "type": "string", "enum": ["wage", "self_employment"] },
                  "tier": { "type": "string" },
                  "monthly_minor": { "type": "integer" }
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
        "author_notes": { "type": "string" },
        "choices": { "type": "array", "items": { "type": "string" } }
      }
    }
    """
}
