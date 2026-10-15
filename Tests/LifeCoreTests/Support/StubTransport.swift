import Foundation
import Testing
@testable import LifeCore

/// A network stand-in: captures requests and replies with a canned status and body.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    var status: Int
    var body: Data
    private(set) var requests: [URLRequest] = []

    init(status: Int = 200, body: String) {
        self.status = status
        self.body = Data(body.utf8)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }

    /// The last request body, parsed.
    func lastBody() throws -> [String: Any] {
        let data = try #require(requests.last?.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

let okResponse = """
{ "id": "msg_1", "type": "message", "role": "assistant", "model": "claude-opus-5-5",
  "content": [ { "type": "text", "text": "{\\"ok\\": true}" } ],
  "stop_reason": "end_turn", "usage": { "input_tokens": 1200, "output_tokens": 340 } }
"""
