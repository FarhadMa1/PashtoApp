/// Word-order tokens. `؟` and `،` stay off the tokens and are removed from the end of `pashto` before comparison.
enum TokenRules {
    static func issues(for item: ContentItem) -> [ValidationIssue] {
        let id = item.id.rawValue
        guard let tokens = item.tokens else {
            var issues: [ValidationIssue] = []
            if item.acceptedOrders != nil {
                issues.append(error(id, "acceptedOrders", "acceptedOrders is set without tokens."))
            }
            if item.tokenPronunciations != nil {
                issues.append(error(id, "tokenPronunciations", "tokenPronunciations is set without tokens."))
            }
            return issues
        }

        var issues: [ValidationIssue] = []
        if tokens.count < 2 {
            issues.append(error(id, "tokens", "tokens need at least 2 entries."))
        }
        for token in tokens {
            if token.isEmpty {
                issues.append(error(id, "tokens", "tokens contain an empty entry."))
            } else if hasEdgeSpace(token) {
                issues.append(error(id, "tokens", "token \"\(token)\" has leading or trailing space."))
            }
            if token.unicodeScalars.contains(PashtoScript.arabicQuestion)
                || token.unicodeScalars.contains(PashtoScript.arabicComma) {
                issues.append(error(id, "tokens", "token \"\(token)\" contains ؟ or ،."))
            }
            issues.append(contentsOf: PashtoScript.issues(in: token, id: id, field: "tokens"))
        }

        let joined = tokens.joined(separator: " ")
        let expected = pashtoWithoutFixedEnding(item.pashto)
        if !sameScalars(joined, expected) {
            issues.append(error(
                id,
                "tokens",
                "tokens join to \"\(joined)\", which does not match pashto without a trailing ؟ or ، (\"\(expected)\")."
            ))
        }

        if let spoken = item.tokenPronunciations {
            if spoken.count != tokens.count {
                issues.append(error(
                    id,
                    "tokenPronunciations",
                    "tokenPronunciations has \(spoken.count) entries and tokens has \(tokens.count)."
                ))
            } else {
                for pronunciation in spoken {
                    if Text.isBlank(pronunciation) {
                        issues.append(error(id, "tokenPronunciations", "tokenPronunciations contains an empty entry."))
                    } else if hasEdgeSpace(pronunciation) {
                        issues.append(error(
                            id,
                            "tokenPronunciations",
                            "token pronunciation \"\(pronunciation)\" has leading or trailing space."
                        ))
                    }
                }
            }
        } else {
            issues.append(error(id, "tokenPronunciations", "tokenPronunciations is required when tokens are set."))
        }

        if let orders = item.acceptedOrders {
            issues.append(contentsOf: orderIssues(orders, count: tokens.count, id: id))
        }
        return issues
    }

    private static func orderIssues(_ orders: [[Int]], count: Int, id: String) -> [ValidationIssue] {
        let identity = Array(0..<count)
        let domain = Set(identity)
        var seen: [[Int]] = []
        var issues: [ValidationIssue] = []
        for order in orders {
            if order.count != count || Set(order) != domain {
                issues.append(error(id, "acceptedOrders", "acceptedOrders entry \(order) is not a permutation of 0..\(max(count - 1, 0))."))
            } else if order == identity {
                issues.append(error(id, "acceptedOrders", "acceptedOrders entry \(order) repeats the original token order."))
            } else if seen.contains(order) {
                issues.append(error(id, "acceptedOrders", "acceptedOrders repeats \(order)."))
            } else {
                seen.append(order)
            }
        }
        return issues
    }

    /// `pashto` with trailing spaces, `؟`, and `،` removed. Word tiles join to this.
    static func pashtoWithoutFixedEnding(_ pashto: String) -> String {
        splitFixedEnding(pashto).body
    }

    /// Trailing `؟` and `،` in the order they appear. Spaces between them are dropped.
    ///
    /// These marks are drawn after the tiles. They are never tiles themselves.
    static func fixedEnding(of pashto: String) -> String {
        splitFixedEnding(pashto).ending
    }

    private static func splitFixedEnding(_ pashto: String) -> (body: String, ending: String) {
        var scalars = Array(Normalization.unicodeScalars(Normalization.nfc(pashto)))
        var ending: [Unicode.Scalar] = []
        while let last = scalars.last {
            if last == " " || last == PashtoScript.arabicQuestion || last == PashtoScript.arabicComma {
                scalars.removeLast()
                if last != " " {
                    ending.append(last)
                }
                continue
            }
            break
        }
        ending.reverse()
        return (String(String.UnicodeScalarView(scalars)), String(String.UnicodeScalarView(ending)))
    }

    private static func sameScalars(_ left: String, _ right: String) -> Bool {
        Normalization.unicodeScalars(Normalization.nfc(left)).elementsEqual(Normalization.unicodeScalars(Normalization.nfc(right)))
    }

    private static func hasEdgeSpace(_ token: String) -> Bool {
        guard let first = token.first, let last = token.last else { return false }
        return first.isWhitespace || last.isWhitespace
    }

    private static func error(_ id: String, _ field: String, _ message: String) -> ValidationIssue {
        ValidationIssue(id: id, field: field, message: message, severity: .error)
    }
}
