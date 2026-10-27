/// Calendar check for `verification.checkedOn`.
///
/// Accepts `YYYY-MM-DD` and `YYYY-MM-DDTHH:MM:SS` with an optional fraction and
/// a `Z` or numeric offset. The check is arithmetic on the text. It does not
/// read the clock.
enum ISO8601Date {
    static func isValid(_ text: String) -> Bool {
        var parser = Parser(text)
        guard let year = parser.digits(4),
              parser.eat("-"),
              let month = parser.digits(2),
              parser.eat("-"),
              let day = parser.digits(2),
              month >= 1, month <= 12,
              day >= 1, day <= days(in: month, year: year)
        else { return false }

        if parser.eat("T") || parser.eat("t") {
            guard let hour = parser.digits(2),
                  parser.eat(":"),
                  let minute = parser.digits(2),
                  parser.eat(":"),
                  let second = parser.digits(2),
                  hour <= 23, minute <= 59, second <= 60
            else { return false }
            if parser.eat(".") {
                guard parser.digits(1) != nil else { return false }
                while parser.digits(1) != nil {}
            }
            if parser.eat("Z") || parser.eat("z") {
                // UTC designator.
            } else if parser.eat("+") || parser.eat("-") {
                guard let offsetHour = parser.digits(2), offsetHour <= 23 else { return false }
                if parser.eat(":") {
                    guard let offsetMinute = parser.digits(2), offsetMinute <= 59 else { return false }
                } else if let offsetMinute = parser.digits(2) {
                    guard offsetMinute <= 59 else { return false }
                }
            }
        }
        return parser.isAtEnd
    }

    private static func days(in month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12:
            return 31
        case 4, 6, 9, 11:
            return 30
        case 2:
            return isLeap(year) ? 29 : 28
        default:
            return 0
        }
    }

    private static func isLeap(_ year: Int) -> Bool {
        if year % 400 == 0 { return true }
        if year % 100 == 0 { return false }
        return year % 4 == 0
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        var index = 0

        init(_ text: String) {
            scalars = Array(text.unicodeScalars)
        }

        var isAtEnd: Bool { index == scalars.count }

        mutating func eat(_ expected: Unicode.Scalar) -> Bool {
            guard index < scalars.count, scalars[index] == expected else { return false }
            index += 1
            return true
        }

        mutating func digits(_ count: Int) -> Int? {
            guard index + count <= scalars.count else { return nil }
            var value = 0
            for offset in 0..<count {
                let scalar = scalars[index + offset]
                guard scalar >= "0", scalar <= "9" else { return nil }
                value = value * 10 + Int(scalar.value - Unicode.Scalar("0").value)
            }
            index += count
            return value
        }
    }
}
