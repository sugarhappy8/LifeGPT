import Foundation
import LifeCore

private let usage = """
    usage: lifelab voice --scenarios FILE --seed FILE [--runs N] [--model ID] [--effort E]
                         [--no-fallback] [--yes] [--out FILE]
    Needs ANTHROPIC_API_KEY in the environment. Nothing is sent without --yes.

    """

private func fail(_ message: String, code: Int32 = 2) -> Int32 {
    FileHandle.standardError.write(Data("\(message)\n\(usage)".utf8))
    return code
}

private struct VoiceReport: Codable {
    var model: String
    var effort: String
    var runs: Int
    var date: String
    var total: Int
    var passed: Int
    var jsonValidFirstTry: Int
    var outcomes: [ScenarioOutcome]
}

/// Phase 1 voice lab: plays fixed scenarios through the real pipeline against
/// the real Anthropic API, so prose and money-claim handling can be judged.
func runVoice(_ args: [String]) async -> Int32 {
    var values: [String: String] = [:]
    var flags: Set<String> = []
    var i = 0
    while i < args.count {
        if ["--yes", "--no-fallback"].contains(args[i]) { flags.insert(args[i]); i += 1; continue }
        guard args[i].hasPrefix("--"), i + 1 < args.count else { return fail("unexpected argument: \(args[i])") }
        values[String(args[i].dropFirst(2))] = args[i + 1]
        i += 2
    }
    guard let scenariosPath = values["scenarios"], let seedPath = values["seed"] else {
        return fail("--scenarios and --seed are required")
    }
    let model = values["model"] ?? "claude-opus-5-5"
    let effort = values["effort"] ?? "medium"
    let runs = max(1, values["runs"].flatMap { Int($0) } ?? 3)

    let scenarios: [VoiceScenario]
    let seed: VoiceSeed
    do {
        scenarios = try VoiceScenario.load(from: URL(fileURLWithPath: scenariosPath))
        seed = try VoiceSeed.load(from: URL(fileURLWithPath: seedPath))
    } catch {
        return fail("could not read the fixtures: \(error)")
    }

    let calls = scenarios.count * runs
    print("Voice lab: \(scenarios.count) scenarios x \(runs) runs = \(calls) turns on \(model) (effort \(effort)).")
    print("Each turn is one API call, plus one repair call when the reply is unusable or rejected.")
    if let cost = VoiceCost.estimateUSD(model: model, calls: calls) {
        print(String(format: "Rough cost: $%.2f to $%.2f (about 4k input and 4k output tokens per call).",
                     cost.lowerBound, cost.upperBound))
    } else {
        print("No price is known for \(model); check your provider's pricing.")
    }
    guard flags.contains("--yes") else {
        print("Nothing was sent. Re-run with --yes to spend the money above.")
        return 3
    }
    guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !apiKey.isEmpty else {
        return fail("ANTHROPIC_API_KEY is not set in the environment")
    }

    let provider = AnthropicProvider(apiKey: apiKey, model: model, effort: effort,
                                     useRefusalFallback: !flags.contains("--no-fallback"))
    let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("lifelab-voice-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: workDir) }

    var outcomes: [ScenarioOutcome] = []
    do {
        let library = try ChatLibrary(directory: workDir)
        for (s, scenario) in scenarios.enumerated() {
            for run in 1...runs {
                let store = try seed.makeChat(in: library)
                let processor = TurnProcessor(store: store, narrator: LLMNarrator(provider: provider),
                                              fate: SeededFate(seed: UInt64(s * 100 + run)))
                print("\n[\(scenario.id) #\(run)] > \(scenario.input)")
                do {
                    let result = try await processor.play(scenario.input)
                    let log = try store.turnLogs().last ?? TurnLog(fate: 0, rejections: [], repaired: false,
                                                                    inputTokens: 0, outputTokens: 0)
                    let outcome = try ScenarioEvaluator.evaluate(scenario, result: result, store: store, log: log)
                    outcomes.append(outcome)
                    print(String(result.text.prefix(500)))
                    for r in outcome.rejections { print("  rejected: \(r)") }
                    print("  pass=\(outcome.pass) validJSONFirstTry=\(outcome.jsonValidFirstTry) "
                          + "attempted=\(Money.format(outcome.attemptedGainMinor, economy: .sampleUS2005)) "
                          + "accepted=\(Money.format(outcome.acceptedGainMinor, economy: .sampleUS2005)) "
                          + "tokens=\(outcome.inputTokens)/\(outcome.outputTokens)")
                } catch ProviderError.http(let status, let body) where [400, 401, 403, 404].contains(status) {
                    // A configuration problem, not a one-off: stop before spending more.
                    return fail("HTTP \(status) from the API; stopping.\n\(body)", code: 1)
                } catch {
                    print("  error: \(error)")
                    outcomes.append(ScenarioOutcome(id: scenario.id, jsonValidFirstTry: false, acceptedGainMinor: 0,
                                                    attemptedGainMinor: 0, rejections: [], pass: false,
                                                    inputTokens: 0, outputTokens: 0, error: "\(error)"))
                }
            }
        }
    } catch {
        return fail("lab setup failed: \(error)", code: 1)
    }

    let report = VoiceReport(model: model, effort: effort, runs: runs,
                             date: ISO8601DateFormatter().string(from: Date()), total: outcomes.count,
                             passed: outcomes.filter(\.pass).count,
                             jsonValidFirstTry: outcomes.filter(\.jsonValidFirstTry).count, outcomes: outcomes)
    print("\nSummary: \(report.passed)/\(report.total) passed, valid JSON first try \(report.jsonValidFirstTry)/\(report.total).")

    let outPath = values["out"] ?? ".lifelab/voice-report.json"
    do {
        let url = URL(fileURLWithPath: outPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = OutputCoding.encoder
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url)
        print("Report written to \(outPath)")
    } catch {
        print("Could not write the report: \(error)")
    }
    return 0
}
