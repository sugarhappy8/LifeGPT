import Foundation
import LifeCore

struct AppSettings: Codable, Equatable {
    enum Provider: String, Codable, CaseIterable, Identifiable {
        case demo, anthropic, gemini, local
        var id: String { rawValue }
        var title: String {
            switch self { case .demo: "Offline demo"; case .anthropic: "Anthropic"; case .gemini: "Google Gemini"; case .local: "Local model" }
        }
    }
    var provider: Provider = .demo
    var anthropicModel = "claude-opus-5-5"
    var geminiModel = "gemini-3.8-flash"
    var localModel = ""
    var localServer = "http://localhost:1234/v1"
    var contextTokens = 32_768
    var localStructuredOutput = false
    var localTwoStep = true
    var cloudTwoStep = false
    var dailyLimitUSD = 5.0
    // User-editable estimates, not a live pricing feed. Local/demo calls always cost zero.
    var inputUSDPerMillion = 4.0
    var outputUSDPerMillion = 20.0
    var appearance = "system"
    var readingSize = 17.0
    var showSuggestions = true
    var model: String {
        switch provider { case .demo: "Built-in"; case .anthropic: anthropicModel; case .gemini: geminiModel; case .local: localModel }
    }
    var usesCloud: Bool { provider == .anthropic || provider == .gemini }
    func validate() throws {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (16_384...1_000_000).contains(contextTokens),
              dailyLimitUSD.isFinite, dailyLimitUSD >= 0,
              inputUSDPerMillion.isFinite, outputUSDPerMillion.isFinite,
              inputUSDPerMillion >= 0, outputUSDPerMillion >= 0 else {
            throw ValidationError.invalid("Check the model, context size (16,384–1,000,000), and spending settings.")
        }
        if usesCloud, dailyLimitUSD > 0, inputUSDPerMillion <= 0 || outputUSDPerMillion <= 0 {
            throw ValidationError.invalid("Enter positive input and output rates to enable an estimated spending limit.")
        }
    }
}

struct AppPaths {
    let root: URL
    var chats: URL { root.appendingPathComponent("Lives", isDirectory: true) }
    var settings: URL { root.appendingPathComponent("settings.json") }
    var usage: URL { root.appendingPathComponent("usage.json") }
    init(root directory: URL? = nil) throws {
        if let directory { root = directory }
        else if let override = ProcessInfo.processInfo.environment["LIFEGPT_DATA_DIR"], !override.isEmpty {
            root = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true).appendingPathComponent("LifeGPT", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
}
