import Foundation
import LifeCore

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case nil:
    print(LifeCore.version)
case "mock":
    exit(await runMock(Array(arguments.dropFirst())))
case "voice":
    exit(await runVoice(Array(arguments.dropFirst())))
default:
    FileHandle.standardError.write(Data("usage: lifelab [mock ...|voice ...]\n".utf8))
    exit(2)
}
