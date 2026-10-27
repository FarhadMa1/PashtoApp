/// Word-order tokens. `؟` and `،` stay off the tokens and are removed from the end of `pashto` before comparison.
enum TokenRules {
    static func issues(for item: ContentItem) -> [ValidationIssue] {
        let id = item.id.rawValue
        guard let tokens = item.tokens else {
            if item.acceptedOrders != nil {
                return [error(id, "acceptedOrders", "acceptedOrders is set without tokens.")]
            }
            return []
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
        let expected = stripTrailingPunctuation(Normalization.nfc(item.pashto))
        if !sameScalars(joined, expected) {
            issues.append(error(
                id,
                "tokens",
                "tokens join to \"\(joined)\", which does not match pashto without a trailing ؟ or ، (\"\(expected)\")."
            ))
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

    private static func stripTrailingPunctuation(_ text: String) -> String {
        var scalars = Array(Normalization.unicodeScalars(text))
        while let last = scalars.last {
            if last == " " || last == PashtoScript.arabicQuestion || last == PashtoScript.arabicComma {
                scalars.removeLast()
                continue
            }
            break
        }
        return String(String.UnicodeScalarView(scalars))
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
