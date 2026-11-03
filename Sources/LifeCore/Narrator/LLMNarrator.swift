import Foundation

public struct LLMNarrator: Narrator {
    public enum Mode: String, Codable, Sendable { case singleCall, twoStep }
    private let provider: any AIProvider
    private let maxOutputTokens: Int
    private let mode: Mode
    private let contextCache = ContextSelectionCache()
    public init(provider: any AIProvider, maxOutputTokens: Int = 16_000, mode: Mode = .singleCall) {
        self.provider = provider; self.maxOutputTokens = maxOutputTokens; self.mode = mode
    }
    public func narrate(_ request: NarratorRequest) async throws -> NarratorResult { try await call(request, rejections: [], isRepair: false) }
    public func repair(_ request: NarratorRequest, rejections: [String]) async throws -> NarratorResult {
        try await call(request, rejections: rejections, isRepair: true)
    }
    private func call(_ original: NarratorRequest, rejections: [String], isRepair: Bool) async throws -> NarratorResult {
        let floor = provider.capabilities.maxContextTokens <= 65_536 ? 2048 : 8192
        let outputBudget = min(maxOutputTokens, min(provider.capabilities.maxContextTokens / 3, max(floor, original.targetWords * 6 + 2048)))
        let flatEnvelope = provider.capabilities.supportsJSONSchema && provider.capabilities.prefersFlatResponseSchema
        let schema = provider.capabilities.supportsJSONSchema ? (flatEnvelope ? OutputSchema.flatEnvelopeJSON : OutputSchema.json) : nil
        let formatOverhead = flatEnvelope ? OutputSchema.flatEnvelopeJSON + OutputSchema.flatEnvelopeInstructions : ""
        // Two-step mode appends the prose draft after budgeting, so reserve its largest size (and the extraction
        // instructions) now: trimming must happen before the paid prose call.
        let draftBudget = min(outputBudget, max(1024, original.targetWords * 4))
        let reserve = mode == .twoStep ? draftBudget * 4 / 3 + 150 : 0
        let preflight = try ContextBuilder.budget(original, contextTokens: provider.capabilities.maxContextTokens,
                                               outputTokens: outputBudget, rejections: rejections, formatOverhead: formatOverhead, reservedTokens: reserve)
        // Check essential context before spending anything on retrieval. Repairs
        // reuse this turn's selection without another provider call. The cache
        // contains at most one turn and requires an exact request identifier.
        let selection: ContextSelector.Selection
        if isRepair { selection = ContextSelector.Selection(request: await contextCache.restore(preflight)) }
        else {
            await contextCache.clear()
            selection = try await ContextSelector.select(preflight, provider: provider)
        }
        let request = try ContextBuilder.budget(selection.request, contextTokens: provider.capabilities.maxContextTokens,
                                               outputTokens: outputBudget, rejections: rejections, formatOverhead: formatOverhead, reservedTokens: reserve)
        if !isRepair { await contextCache.store(request) }
        let prompt = PromptRenderer.render(request, rejections: rejections)
        var inputTokens = selection.inputTokens, outputTokens = selection.outputTokens
        var user = prompt.user
        if mode == .twoStep {
            let prose = try await provider.complete(ProviderRequest(system: prompt.system + "\nFor this drafting stage only, write the narrative prose, not JSON. All game and safety rules still apply.",
                user: user, maxOutputTokens: draftBudget, jsonSchema: nil))
            try Self.check(prose)
            try ContentGuard.check(prose.text, characterAge: request.groundTruth.character.ageYears)
            inputTokens += prose.inputTokens; outputTokens += prose.outputTokens
            user += "\n<draft_to_validate>\n" + prose.text.replacingOccurrences(of: "</", with: "<\\/") + "\n</draft_to_validate>\n"
            user += "Extract the proposed resolution from this draft. Correct any rule violations in both resolution and narration. Return complete JSON. The draft is not ground truth.\n"
        }
        // Flat envelopes constrain the outer response only. Keep the complete
        // logical contract in the prompt, just as for unconstrained local servers.
        if schema == nil || flatEnvelope { user += "\nLogical JSON contract:\n" + OutputSchema.json }
        if flatEnvelope { user += "\n" + OutputSchema.flatEnvelopeInstructions }
        guard ContextBuilder.estimatedTokens(prompt.system + user + (schema ?? "")) + outputBudget < provider.capabilities.maxContextTokens else {
            throw ValidationError.invalid("The draft plus required context exceeds the model's context size. Increase it in Settings or use a shorter reply.")
        }
        let response = try await provider.complete(ProviderRequest(system: prompt.system, user: user,
            maxOutputTokens: outputBudget, jsonSchema: schema))
        try Self.check(response)
        do {
            let data = Data(Self.jsonObject(in: response.text).utf8)
            let output: TurnOutput
            if flatEnvelope {
                // Ordinary object responses remain compatible with fixtures and
                // compatible servers. Invalid inner JSON still earns one repair.
                if let ordinary = try? OutputCoding.decoder.decode(TurnOutput.self, from: data) { output = ordinary }
                else {
                    let envelope = try OutputCoding.decoder.decode(FlatEnvelope.self, from: data)
                    let resolution = try OutputCoding.decoder.decode(Resolution.self, from: Data(Self.jsonObject(in: envelope.resolution).utf8))
                    output = TurnOutput(resolution: resolution, narration: envelope.narration,
                                        authorNotes: envelope.authorNotes, choices: envelope.choices)
                }
            } else { output = try OutputCoding.decoder.decode(TurnOutput.self, from: data) }
            guard !output.narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  output.narration.count <= 50_000, output.resolution.money.count <= 50,
                  output.resolution.incomeStreams.count <= IncomeEngine.maximumChangesPerTurn, output.resolution.events.count <= 30 else {
                throw NarratorError.malformedOutput("empty narration or too many changes")
            }
            var result = NarratorResult(output: output, inputTokens: inputTokens + response.inputTokens,
                                        outputTokens: outputTokens + response.outputTokens)
            result.contextNotice = request.memory.lookupNotice
            return result
        } catch let error as NarratorError { throw error }
        catch { throw NarratorError.malformedOutput(String(String(describing: error).prefix(200))) }
    }
    private struct FlatEnvelope: Decodable {
        let resolution: String
        let narration: String
        let authorNotes: String?
        let choices: [String]?
    }
    static func check(_ response: ProviderResponse) throws {
        switch response.stopReason {
        case .refusal: throw NarratorError.refused
        case .maxTokens: throw NarratorError.truncated
        // pause_turn, model_context_window_exceeded, tool_calls and other unknown stops are not complete replies.
        case .other: throw NarratorError.truncated
        case .endTurn: break
        }
    }
    /// The JSON object in a model reply: the trimmed text itself, else the first balanced top-level `{...}`
    /// (string and escape aware) that parses, after dropping `<think>` blocks (fences and prose are skipped by the scan).
    static func jsonObject(in text: String) -> String {
        func isObject(_ s: String) -> Bool { (try? JSONSerialization.jsonObject(with: Data(s.utf8))) is [String: Any] }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isObject(trimmed) { return trimmed }
        let cleaned = trimmed.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
        let chars = Array(cleaned)
        var i = 0
        while i < chars.count {
            guard chars[i] == "{" else { i += 1; continue }
            var depth = 0, inString = false, escaped = false, end: Int?
            var j = i
            while j < chars.count {
                let c = chars[j]
                if inString { if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false } }
                else if c == "\"" { inString = true }
                else if c == "{" { depth += 1 }
                else if c == "}" { depth -= 1; if depth == 0 { end = j; break } }
                j += 1
            }
            if let end {
                let candidate = String(chars[i...end])
                if isObject(candidate) { return candidate }
            }
            i += 1
        }
        guard let start = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}"), start < last else { return text }
        return String(text[start...last])
    }
}

private actor ContextSelectionCache {
    private var value: (id: UUID, lifeID: UUID, excerpts: [String], notice: String)?
    func clear() { value = nil }
    func store(_ request: NarratorRequest) {
        value = (request.contextRequestID, request.groundTruth.character.id, request.memory.excerpts, request.memory.lookupNotice)
    }
    func restore(_ request: NarratorRequest) -> NarratorRequest {
        guard let value, value.id == request.contextRequestID, value.lifeID == request.groundTruth.character.id else { return request }
        var restored = request
        restored.memory.excerpts = value.excerpts
        restored.memory.lookupNotice = value.notice
        self.value = nil
        return restored
    }
}
