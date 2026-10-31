import Foundation

public enum ContentCommand {
    public static func main(_ arguments: [String]) -> Int32 {
        switch run(arguments) {
        case .success(let text):
            if !text.isEmpty {
                print(text)
            }
            return 0
        case .failure(let failure):
            if !failure.text.isEmpty {
                print(failure.text)
            }
            return failure.code
        }
    }

    static func run(_ arguments: [String]) -> Result<String, Failure> {
        var args = arguments
        guard let command = args.first else {
            return .failure(Failure(code: 2, text: usage))
        }
        args.removeFirst()
        switch command {
        case "merge":
            return merge(args)
        case "validate":
            return validate(args)
        case "-h", "--help", "help":
            return .success(usage)
        default:
            return .failure(Failure(code: 2, text: usage))
        }
    }

    private static func merge(_ arguments: [String]) -> Result<String, Failure> {
        guard let options = Options(arguments, command: "merge") else {
            return .failure(Failure(code: 2, text: usage))
        }
        if options.check {
            let issues = ContentMerger.checkCommittedBundle(root: options.root)
            if IssueList.hasError(issues) {
                return .failure(Failure(code: 1, text: IssueList.format(issues)))
            }
            return .success("")
        }
        let outcome = ContentMerger.merge(root: options.root)
        if IssueList.hasError(outcome.issues) {
            return .failure(Failure(code: 1, text: IssueList.format(outcome.issues)))
        }
        guard let bytes = outcome.bytes else {
            return .failure(Failure(code: 1, text: "content.json could not be encoded."))
        }
        let destination = ContentRoot(url: options.root).bundleFile
        do {
            try bytes.write(to: destination, options: .atomic)
        } catch {
            return .failure(Failure(code: 1, text: "Could not write \(destination.path): \(error)"))
        }
        return .success("")
    }

    private static func validate(_ arguments: [String]) -> Result<String, Failure> {
        guard let options = Options(arguments, command: "validate"), let mode = options.mode else {
            return .failure(Failure(code: 2, text: usage))
        }
        let issues = ContentCheck.issues(root: options.root, mode: mode)
        let text = IssueList.format(issues)
        if IssueList.hasError(issues) {
            return .failure(Failure(code: 1, text: text))
        }
        return .success(text)
    }

    private static let usage = """
    pashto-content merge [--check] [--root <directory>]
    pashto-content validate --mode dev|release [--root <directory>]
    """

    struct Failure: Error {
        var code: Int32
        var text: String
    }

    struct Options {
        var root: URL
        var check = false
        var mode: ToolMode?

        init?(_ arguments: [String], command: String) {
            var index = 0
            var rootPath = FileManager.default.currentDirectoryPath
            while index < arguments.count {
                let argument = arguments[index]
                switch argument {
                case "--check":
                    guard command == "merge" else { return nil }
                    check = true
                    index += 1
                case "--root":
                    guard index + 1 < arguments.count else { return nil }
                    rootPath = arguments[index + 1]
                    index += 2
                case "--mode":
                    guard command == "validate", index + 1 < arguments.count, let parsed = ToolMode(rawValue: arguments[index + 1]) else {
                        return nil
                    }
                    mode = parsed
                    index += 2
                default:
                    return nil
                }
            }
            if command == "validate", mode == nil { return nil }
            root = URL(fileURLWithPath: rootPath)
        }
    }
}
