import Foundation
import LifeCore

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case nil:
    print(LifeCore.version)
case "mock":
    exit(await runMock(Array(arguments.dropFirst())))
default:
    FileHandle.standardError.write(Data("usage: lifelab [mock ...]\n".utf8))
    exit(2)
}
