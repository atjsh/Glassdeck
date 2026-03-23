import Foundation
import ArgumentParser
import GlassdeckBuildCore

@main
struct GlassdeckBuildExecutable {
    static func main() async {
        await RootCommand.main()
    }
}
