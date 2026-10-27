import Foundation

/// Scholarly transliteration: no Arabic-script scalars, and U+0301 only on a vowel.
enum TranslitRules {
    static func issues(in translit: String, id: String?) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var reportedArabic: Set<Unicode.Scalar> = []
        for scalar in translit.unicodeScalars where isArabicScript(scalar) {
            if reportedArabic.insert(scalar).inserted {
                issues.append(error(id, "translit contains Arabic script (\(PashtoScript.code(scalar)))."))
            }
        }
        issues.append(contentsOf: acuteIssues(in: translit, id: id))
        return issues
    }

    private static func acuteIssues(in translit: String, id: String?) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var lastBase: Unicode.Scalar?
        var reportedBases: Set<Unicode.Scalar> = []
        var reportedBare = false
        for scalar in translit.decomposedStringWithCanonicalMapping.unicodeScalars {
            if isMark(scalar) {
                guard scalar == Normalization.stressScalar else { continue }
                guard let base = lastBase else {
                    if !reportedBare {
                        reportedBare = true
                        issues.append(error(id, "translit has a stress mark with no base letter."))
                    }
                    continue
                }
                if !PashtoStressRule.vowelScalars.contains(base), reportedBases.insert(base).inserted {
                    issues.append(error(id, "translit puts a stress mark on \"\(String(base))\", which is not a vowel."))
                }
            } else {
                lastBase = scalar
            }
        }
        return issues
    }

    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return false
        }
    }

    private static func isArabicScript(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF:
            return true
        default:
            return false
        }
    }

    private static func error(_ id: String?, _ message: String) -> ValidationIssue {
        ValidationIssue(id: id, field: "translit", message: message, severity: .error)
    }
}
