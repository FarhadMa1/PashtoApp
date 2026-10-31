import Foundation
import PashtoCore

/// `dev` is the authoring check. `release` adds the release gate.
public enum ToolMode: String, Hashable, Sendable {
    case dev
    case release

    var validationMode: ValidationMode {
        switch self {
        case .dev:
            return .authoring
        case .release:
            return .release
        }
    }
}

public struct SpecialSound: Hashable, Sendable {
    public let character: String
    public let translit: String

    public init(character: String, translit: String) {
        self.character = character
        self.translit = translit
    }
}

public struct RegistryEntry: Hashable, Sendable {
    public let id: String
    public let retired: Bool

    public init(id: String, retired: Bool) {
        self.id = id
        self.retired = retired
    }
}

enum IssueText {
    static func isBlank(_ text: String?) -> Bool {
        guard let text else { return true }
        return text.unicodeScalars.allSatisfy { Character($0).isWhitespace }
    }

    static func make(
        _ severity: ValidationSeverity,
        id: String?,
        field: String,
        _ message: String
    ) -> ValidationIssue {
        ValidationIssue(id: id, field: field, message: message, severity: severity)
    }
}

enum IssueList {
    static func hasError(_ issues: [ValidationIssue]) -> Bool {
        issues.contains { $0.severity == .error }
    }

    static func format(_ issues: [ValidationIssue]) -> String {
        issues.map { issue in
            let id = issue.id ?? ""
            return "\(issue.severity)\t\(id)\t\(issue.field)\t\(issue.message)"
        }.joined(separator: "\n")
    }
}
