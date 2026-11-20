import Foundation

public enum AngleUnit: String, Codable, Sendable { case degrees, radians }

/// Bounded arithmetic, never evaluated as code or sent to another process.
public enum Arithmetic {
    public static let maximumLength = 512
    public static func evaluate(_ text: String, angle: AngleUnit = .degrees) -> Double? {
        guard text.utf8.count <= maximumLength else { return nil }
        var parser = Parser(text, angle: angle)
        guard let value = parser.parse(), value.isFinite else { return nil }
        return value == 0 ? 0 : value
    }

    private struct Parser {
        let characters: [Character]
        let angle: AngleUnit
        var index = 0
        var depth = 0
        typealias Term = (value: Double, percent: Bool)

        init(_ text: String, angle: AngleUnit) {
            characters = Array(text.lowercased())
            self.angle = angle
        }
        mutating func parse() -> Double? {
            guard let value = expression()?.value else { return nil }
            spaces()
            return index == characters.count ? value : nil
        }
        mutating func expression() -> Term? {
            guard var left = term() else { return nil }
            while let op = take("+-−") {
                guard let right = term() else { return nil }
                // A pocket calculator's percentage: 200 + 10% is 220.
                let amount = right.percent ? left.value * right.value : right.value
                left = (op == "+" ? left.value + amount : left.value - amount, false)
            }
            return left
        }
        mutating func term() -> Term? {
            guard var left = unary() else { return nil }
            while true {
                if let op = take("*×/÷") {
                    guard let right = unary() else { return nil }
                    left = (op == "*" || op == "×" ? left.value * right.value : left.value / right.value, false)
                } else {
                    spaces()
                    guard index < characters.count,
                          characters[index] == "(" || characters[index] == "√" || characters[index].isLetter else { return left }
                    guard let right = unary() else { return nil }
                    left = (left.value * right.value, false)
                }
            }
        }
        mutating func unary() -> Term? {
            guard depth < 64 else { return nil }
            depth += 1
            defer { depth -= 1 }
            if take("-−") != nil { return unary().map { (-$0.value, $0.percent) } }
            if take("+") != nil { return unary() }
            if take("√") != nil { return unary().map { ($0.value.squareRoot(), false) } }
            guard var base = postfix() else { return nil }
            if take("^") != nil {
                guard let exponent = unary() else { return nil }
                base = (Foundation.pow(base.value, exponent.value), false)
            }
            return base
        }
        mutating func postfix() -> Term? {
            guard var value = primary() else { return nil }
            var percent = false
            while let op = take("%!") {
                if op == "%" { value /= 100; percent = true }
                else {
                    guard value.isFinite, value >= 0, value <= 170, value.rounded() == value else { return nil }
                    value = value < 2 ? 1 : (2...Int(value)).reduce(1.0) { $0 * Double($1) }
                    percent = false
                }
            }
            return (value, percent)
        }
        mutating func primary() -> Double? {
            guard depth < 64 else { return nil }
            depth += 1
            defer { depth -= 1 }
            spaces()
            if take("(") != nil {
                guard let inner = expression(), take(")") != nil else { return nil }
                return inner.value
            }
            if index < characters.count, characters[index].isLetter {
                let start = index
                while index < characters.count, characters[index].isLetter || characters[index].isNumber { index += 1 }
                let name = String(characters[start..<index])
                if name == "pi" || name == "π" { return .pi }
                if name == "e" { return Foundation.exp(1) }
                guard let argument = primary() else { return nil }
                return function(name, argument)
            }
            return number()
        }
        func function(_ name: String, _ x: Double) -> Double? {
            let radians = angle == .degrees ? x * .pi / 180 : x
            let outputScale = angle == .degrees ? 180 / Double.pi : 1
            switch name {
            case "sqrt": return x.squareRoot()
            case "cbrt": return Foundation.cbrt(x)
            case "abs": return abs(x)
            case "round": return x.rounded()
            case "floor": return floor(x)
            case "ceil": return ceil(x)
            case "sin": return sin(radians)
            case "cos": return cos(radians)
            case "tan": return abs(cos(radians)) < 1e-15 ? nil : tan(radians)
            case "asin": return asin(x) * outputScale
            case "acos": return acos(x) * outputScale
            case "atan": return atan(x) * outputScale
            case "sinh": return sinh(x)
            case "cosh": return cosh(x)
            case "tanh": return tanh(x)
            case "asinh": return asinh(x)
            case "acosh": return acosh(x)
            case "atanh": return atanh(x)
            case "log": return log10(x)
            case "log2": return log2(x)
            case "ln": return log(x)
            case "exp": return exp(x)
            case "pow10": return pow(10, x)
            case "pow2": return pow(2, x)
            default: return nil
            }
        }
        mutating func number() -> Double? {
            spaces()
            let start = index
            while index < characters.count, characters[index].isASCII && (characters[index].isNumber || ".,".contains(characters[index])) { index += 1 }
            guard start < index else { return nil }
            let mantissa = String(characters[start..<index])
            if mantissa.contains(","), mantissa.range(of: #"^[0-9]{1,3}(,[0-9]{3})+(\.[0-9]*)?$"#, options: .regularExpression) == nil { return nil }
            var number = mantissa.replacingOccurrences(of: ",", with: "")
            if index < characters.count, characters[index] == "e" {
                let exponent = index
                index += 1
                if index < characters.count, "+-".contains(characters[index]) { index += 1 }
                while index < characters.count, characters[index].isASCII && characters[index].isNumber { index += 1 }
                number += String(characters[exponent..<index])
            }
            return Double(number)
        }
        mutating func take(_ options: String) -> Character? {
            spaces()
            guard index < characters.count, options.contains(characters[index]) else { return nil }
            index += 1
            return characters[index - 1]
        }
        mutating func spaces() {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
        }
    }
}

public enum NumberText {
    public static func shown(_ value: Double, precision: Int = 10) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = abs(value) >= 1e15 || (value != 0 && abs(value) < 1e-8) ? .scientific : .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = min(14, max(2, precision))
        return formatter.string(from: value as NSNumber) ?? copied(value)
    }
    /// Display rounding never changes subsequent calculations.
    public static func copied(_ value: Double) -> String {
        if value == 0 { return "0" }
        if value.isFinite, abs(value) < 1e15, value.rounded() == value { return String(format: "%.0f", value) }
        return String(value)
    }
}
