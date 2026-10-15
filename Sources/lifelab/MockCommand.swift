import Foundation
import LifeCore

private func fail(_ message: String) -> Int32 {
    FileHandle.standardError.write(Data("""
        \(message)
        usage: lifelab mock --name N --birthplace P --birth-year Y --appearance A --age N
                            [--background T] [--dir D] [--script FILE] [--debug]

        """.utf8))
    return 2
}

/// Phase 0 prototype: play a life in the terminal against the mock narrator.
func runMock(_ args: [String]) async -> Int32 {
    var values: [String: String] = [:]
    var debug = false
    var i = 0
    while i < args.count {
        if args[i] == "--debug" { debug = true; i += 1; continue }
        guard args[i].hasPrefix("--"), i + 1 < args.count else { return fail("unexpected argument: \(args[i])") }
        values[String(args[i].dropFirst(2))] = args[i + 1]
        i += 2
    }
    guard let name = values["name"], let birthplace = values["birthplace"],
          let birthYear = values["birth-year"].flatMap({ Int($0) }),
          let appearance = values["appearance"], let age = values["age"].flatMap({ Int($0) })
    else { return fail("missing or invalid required option") }

    let directory = URL(fileURLWithPath: values["dir"] ?? ".lifelab/chats")
    let lines: [String]
    if let script = values["script"] {
        guard let text = try? String(contentsOfFile: script, encoding: .utf8) else {
            return fail("cannot read script: \(script)")
        }
        lines = text.components(separatedBy: .newlines)
    } else {
        var all: [String] = []
        while let line = readLine() { all.append(line) }
        lines = all
    }

    do {
        let library = try ChatLibrary(directory: directory)
        let character = NewCharacter(name: name, birthplace: birthplace, birthYear: birthYear,
                                     appearance: appearance, startingAge: age, background: values["background"])
        let (_, store) = try library.createChat(character: character, economy: .sampleUS2005)
        let processor = TurnProcessor(store: store, narrator: MockNarrator(), fate: SeededFate(seed: 2026))

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            print("> \(line)")
            do {
                let result = try await processor.play(line)
                switch result.kind {
                case .ignored: continue
                case .outOfCharacter: print(result.text)
                case .narrated:
                    print(result.text)
                    let c = try store.character()
                    let balance = Money.format(try store.balanceMinor(), economy: try store.economy())
                    print("Date: \(c.currentDate.iso) • Age: \(c.ageYears) • Balance: \(balance)")
                    if debug, let log = try store.turnLogs().last {
                        for rejection in log.rejections { print("  rejected: \(rejection)") }
                    }
                }
            } catch TurnError.refused {
                print("(The narrator declined to continue this scene.)")
            } catch {
                print("(Something went wrong: \(error))")
            }
        }
        return 0
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        return 1
    }
}
