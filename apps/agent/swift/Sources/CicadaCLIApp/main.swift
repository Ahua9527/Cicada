import Foundation
import CicadaCLI

let cli = CicadaCLI()
let result = cli.run(arguments: Array(CommandLine.arguments.dropFirst()))

if !result.stdout.isEmpty {
    print(result.stdout)
}
if !result.stderr.isEmpty {
    fputs(result.stderr + "\n", stderr)
}

exit(result.exitCode)
