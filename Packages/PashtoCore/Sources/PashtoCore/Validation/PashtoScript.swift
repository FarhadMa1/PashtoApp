import Foundation

enum Text {
    static func isBlank(_ text: String) -> Bool {
        text.allSatisfy(\.isWhitespace)
    }

    static func isBlank(_ text: String?) -> Bool {
        guard let text else { return true }
        return isBlank(text)
    }
}

/// Afghan orthography checks for `pashto`, tokens, letter names, and letter forms.
enum PashtoScript {
    static let arabicYeh: Unicode.Scalar = "\u{064A}"
    static let arabicKaf: Unicode.Scalar = "\u{0643}"
    static let alefMaksura: Unicode.Scalar = "\u{0649}"
    static let persianGaf: Unicode.Scalar = "\u{06AF}"
    static let zwnj: Unicode.Scalar = "\u{200C}"
    static let zwj: Unicode.Scalar = "\u{200D}"
    static let lrm: Unicode.Scalar = "\u{200E}"
    static let rlm: Unicode.Scalar = "\u{200F}"
    static let nbsp: Unicode.Scalar = "\u{00A0}"
    static let tatweel: Unicode.Scalar = "\u{0640}"
    static let arabicQuestion: Unicode.Scalar = "\u{061F}"
    static let arabicComma: Unicode.Scalar = "\u{060C}"

    /// `allowTatweel` is only for letter `forms`, where U+0640 is the joining mark (`ـځـ`, `ـا`).
    static func issues(in text: String, id: String?, field: String, allowTatweel: Bool = false) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if !Normalization.isNFC(text) {
            issues.append(issue(id, field, "\(field) must be Unicode NFC."))
        }
        if field == "pashto", hasEdgeSpace(text) {
            issues.append(issue(id, field, "pashto has leading or trailing space."))
        }

        var forbidden: Set<Unicode.Scalar> = []
        var invisible: Set<Unicode.Scalar> = []
        var digits: Set<Unicode.Scalar> = []
        var foreign: Set<Unicode.Scalar> = []
        var previousWasSpace = false
        var reportedDoubleSpace = false
        var word: [Unicode.Scalar] = []
        func flushWord() {
            defer { word.removeAll(keepingCapacity: true) }
            guard word.contains(Self.arabicYeh) else { return }
            let earlier = word.dropLast()
            if word.last != Self.arabicYeh || earlier.contains(Self.arabicYeh) {
                let shown = String(String.UnicodeScalarView(word))
                issues.append(
                    issue(id, field, "\(field) uses ي (U+064A) inside \"\(shown)\". It is only allowed at the end of a word.")
                )
            }
        }

        for scalar in text.unicodeScalars {
            if isWordBoundary(scalar) {
                flushWord()
            } else {
                word.append(scalar)
            }
            if isForbidden(scalar), forbidden.insert(scalar).inserted {
                issues.append(issue(id, field, forbiddenMessage(scalar, field: field)))
            }
            if isInvisible(scalar, allowTatweel: allowTatweel), invisible.insert(scalar).inserted {
                issues.append(issue(id, field, "\(field) contains \(name(scalar))."))
            }
            if isDigit(scalar), digits.insert(scalar).inserted {
                issues.append(issue(id, field, "\(field) contains a digit (\(code(scalar)))."))
            }
            if isNonArabicLetter(scalar), foreign.insert(scalar).inserted {
                issues.append(issue(id, field, "\(field) contains \"\(String(scalar))\" (\(code(scalar))), which is not Arabic script."))
            }
            if scalar == " " {
                if previousWasSpace, !reportedDoubleSpace {
                    issues.append(issue(id, field, "\(field) contains a double space."))
                    reportedDoubleSpace = true
                }
                previousWasSpace = true
            } else {
                previousWasSpace = false
            }
        }
        flushWord()
        return issues
    }

    static func containsSequence(_ needle: String, in haystack: String) -> Bool {
        let pin = Normalization.unicodeScalars(Normalization.nfc(needle))
        let hay = Normalization.unicodeScalars(Normalization.nfc(haystack))
        guard !pin.isEmpty, pin.count <= hay.count else { return false }
        let last = hay.count - pin.count
        for start in 0...last {
            if hay[start..<(start + pin.count)].elementsEqual(pin) {
                return true
            }
        }
        return false
    }

    private static func isForbidden(_ scalar: Unicode.Scalar) -> Bool {
        scalar == arabicKaf || scalar == alefMaksura || scalar == persianGaf
    }

    private static func isInvisible(_ scalar: Unicode.Scalar, allowTatweel: Bool) -> Bool {
        if allowTatweel, scalar == tatweel { return false }
        return scalar == zwnj || scalar == zwj || scalar == lrm || scalar == rlm || scalar == nbsp || scalar == tatweel
    }

    private static func isNonArabicLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return !isArabicScript(scalar)
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

    /// Punctuation and whitespace end a word, so ي before ؟ or ، is word-final.
    private static func isWordBoundary(_ scalar: Unicode.Scalar) -> Bool {
        if Character(scalar).isWhitespace { return true }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation:
            return true
        default:
            return false
        }
    }

    private static func hasEdgeSpace(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first, let last = text.unicodeScalars.last else { return false }
        return Character(first).isWhitespace || Character(last).isWhitespace
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x0660...0x0669, 0x06F0...0x06F9:
            return true
        default:
            return false
        }
    }

    private static func forbiddenMessage(_ scalar: Unicode.Scalar, field: String) -> String {
        switch scalar {
        case arabicKaf:
            return "\(field) uses ك (U+0643). Write ک (U+06A9)."
        case alefMaksura:
            return "\(field) uses ى (U+0649). That letter is not used."
        case persianGaf:
            return "\(field) uses گ (U+06AF). Write ګ (U+06AB)."
        default:
            return "\(field) uses \(code(scalar))."
        }
    }

    private static func name(_ scalar: Unicode.Scalar) -> String {
        switch scalar {
        case zwnj: return "ZWNJ (U+200C)"
        case zwj: return "ZWJ (U+200D)"
        case lrm: return "LRM (U+200E)"
        case rlm: return "RLM (U+200F)"
        case nbsp: return "NBSP (U+00A0)"
        case tatweel: return "tatweel (U+0640)"
        default: return code(scalar)
        }
    }

    static func code(_ scalar: Unicode.Scalar) -> String {
        String(format: "U+%04X", scalar.value)
    }

    private static func issue(_ id: String?, _ field: String, _ message: String) -> ValidationIssue {
        ValidationIssue(id: id, field: field, message: message, severity: .error)
    }
}
