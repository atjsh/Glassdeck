import Foundation

public enum CommandLineRendering {
    public static func render(_ invocation: ProcessInvocation) -> String {
        var pieces = [quote(invocation.executable)]
        pieces.append(contentsOf: invocation.arguments.map { quote($0) })
        return pieces.joined(separator: " ")
    }

    public static func quote(_ argument: String) -> String {
        if argument.isEmpty {
            return "''"
        }

        let reservedCharacters = CharacterSet.whitespacesAndNewlines.union(.controlCharacters).union(
            CharacterSet(charactersIn: "'\"\\\\$")
        )
        if argument.rangeOfCharacter(from: reservedCharacters) == nil {
            return argument
        }

        let escaped = argument.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }
}
