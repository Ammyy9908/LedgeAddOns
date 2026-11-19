import Foundation

/// Arithmetic as people type it: + − × ÷ ^, brackets, percentages, and a few functions. "80 + 15%" adds 15% of 80,
/// like a pocket calculator. Anything it doesn't understand is nil, never a guess.
public enum Calculator {
    public static func evaluate(_ text: String) -> Double? {
        var parser = Parser(text)
        guard let value = parser.parse(), value.isFinite else { return nil }
        return value
    }

    /// Whether `text` is a sum rather than a bare number or a word, so the launcher only answers what was asked.
    public static func looksLikeMath(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespaces).lowercased()
        let startsWithFunction = text.hasPrefix("√") || Parser.functions.keys.contains { text.hasPrefix($0) }
        let startsLikeNumber = text.first.map { $0.isNumber || "(-−.".contains($0) } ?? false
        guard startsWithFunction || startsLikeNumber else { return false }
        return startsWithFunction || text.dropFirst().contains { "+-−*/×÷^%()".contains($0) }
    }

    private struct Parser {
        static let functions: [String: @Sendable (Double) -> Double] = [
            "sqrt": { $0.squareRoot() }, "abs": { Swift.abs($0) }, "round": { $0.rounded() },
            "sin": { Foundation.sin($0) }, "cos": { Foundation.cos($0) }, "tan": { Foundation.tan($0) },
            "log": { Foundation.log10($0) }, "ln": { Foundation.log($0) },
        ]

        private let characters: [Character]
        private var index = 0

        init(_ text: String) {
            // Thousands separators go: "1,250 / 5" is 1250 / 5.
            characters = Array(text.lowercased().replacingOccurrences(of: #"(?<=\d),(?=\d{3})"#, with: "", options: .regularExpression))
        }

        mutating func parse() -> Double? {
            guard let value = expression()?.value else { return nil }
            skipSpaces()
            return index == characters.count ? value : nil
        }

        /// A value, and whether it was written as a percentage, which + and − take of the left side.
        private typealias Term = (value: Double, percent: Bool)

        private mutating func expression() -> Term? {
            guard var left = term() else { return nil }
            while let op = take(["+", "-", "−"]) {
                guard let right = term() else { return nil }
                let amount = right.percent ? left.value * right.value : right.value
                left = (op == "+" ? left.value + amount : left.value - amount, false)
            }
            return left
        }

        private mutating func term() -> Term? {
            guard var left = power() else { return nil }
            while let op = take(["*", "×", "/", "÷"]) {
                guard let right = power() else { return nil }
                left = (op == "*" || op == "×" ? left.value * right.value : left.value / right.value, false)
            }
            return left
        }

        private mutating func power() -> Term? {
            guard let base = unary() else { return nil }
            guard take(["^"]) != nil else { return base }
            guard let exponent = power() else { return nil }
            return (Foundation.pow(base.value, exponent.value), false)
        }

        private mutating func unary() -> Term? {
            if take(["-", "−"]) != nil { return unary().map { (-$0.value, $0.percent) } }
            if take(["+"]) != nil { return unary() }
            if take(["√"]) != nil { return unary().map { ($0.value.squareRoot(), false) } }
            guard var value = primary() else { return nil }
            var percent = false
            while take(["%"]) != nil {
                value /= 100
                percent = true
            }
            return (value, percent)
        }

        private mutating func primary() -> Double? {
            skipSpaces()
            if take(["("]) != nil {
                guard let inner = expression(), take([")"]) != nil else { return nil }
                return inner.value
            }
            if let word = word() {
                if word == "pi" || word == "π" { return .pi }
                if word == "e" { return M_E }
                guard let function = Self.functions[word], let argument = primary() else { return nil }
                return function(argument)
            }
            return number()
        }

        private mutating func number() -> Double? {
            skipSpaces()
            let start = index
            while index < characters.count, characters[index].isNumber || characters[index] == "." { index += 1 }
            return start == index ? nil : Double(String(characters[start..<index]))
        }

        private mutating func word() -> String? {
            skipSpaces()
            let start = index
            while index < characters.count, characters[index].isLetter || characters[index] == "π" { index += 1 }
            return start == index ? nil : String(characters[start..<index])
        }

        private mutating func take(_ options: [Character]) -> Character? {
            skipSpaces()
            guard index < characters.count, options.contains(characters[index]) else { return nil }
            index += 1
            return characters[index - 1]
        }

        private mutating func skipSpaces() {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
        }
    }
}

/// Numbers as the launcher shows them: grouped, at most 10 decimals, no trailing zeros.
public enum NumberText {
    public static func shown(_ value: Double) -> String { format(value, grouping: true) }
    /// For the clipboard, without grouping, so it pastes into a spreadsheet or another sum.
    public static func copied(_ value: Double) -> String { format(value, grouping: false) }

    private static func format(_ value: Double, grouping: Bool) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = Swift.abs(value) < 1e-4 && value != 0 ? 14 : 10
        if Swift.abs(value) >= 1e15 { formatter.numberStyle = .scientific }
        return formatter.string(from: value as NSNumber) ?? "\(value)"
    }
}
