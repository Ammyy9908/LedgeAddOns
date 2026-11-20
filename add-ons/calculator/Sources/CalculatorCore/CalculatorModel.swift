import Foundation
import LedgeKit

public enum CalculatorView: String, Codable, Sendable { case basic, scientific, typing, history }
public struct Calculation: Codable, Sendable, Equatable {
    public var id: String
    public var expression: String
    public var result: Double
    public var angle: AngleUnit
}
public struct CalculatorState: Codable, Sendable, Equatable {
    public var angle: AngleUnit = .degrees
    public var precision = 10
    public var defaultView: CalculatorView = .basic
    public var keepHistory = true
    public var history: [Calculation] = []
    public init() {}
}
public enum CalculatorEffect: Sendable, Equatable { case copy(String), openPage, holdOpen(Bool) }

/// Calculator state and controls, independent of the running Ledge session.
public struct CalculatorModel: Sendable {
    public private(set) var saved: CalculatorState
    public private(set) var expression = ""
    public private(set) var memory = 0.0
    public private(set) var view: CalculatorView
    public private(set) var second = false
    public private(set) var pinned = false
    public private(set) var keypadView: CalculatorView
    public private(set) var notice: String?
    private var didEvaluate = false

    public init(saved: CalculatorState = .init()) {
        var clean = saved
        if clean.defaultView == .typing { clean.defaultView = .basic }
        clean.precision = min(14, max(2, clean.precision))
        clean.history = Array(clean.history.filter { $0.result.isFinite && $0.expression.utf8.count <= Arithmetic.maximumLength && $0.id.count <= 64 }.prefix(50))
        self.saved = clean
        view = clean.defaultView
        keypadView = clean.defaultView == .scientific ? .scientific : .basic
    }
    public var value: Double? { expression.isEmpty ? 0 : Arithmetic.evaluate(expression, angle: saved.angle) }
    public var resultText: String { value.map { NumberText.shown($0, precision: saved.precision) } ?? "—" }
    public mutating func showNotice(_ text: String) { notice = text }
    public mutating func pinFailed() { pinned = false; notice = "Pin unavailable." }

    @discardableResult public mutating func handle(_ event: SurfaceEvent) -> CalculatorEffect? {
        guard [Surface.notchPage, Surface.widget, Surface.settingsPage, Surface.shortcut].contains(event.surface) else { return nil }
        notice = nil
        if event.surface == Surface.settingsPage {
            switch (event.control, event.action) {
            case ("angle", .picked(let unit)): if let angle = AngleUnit(rawValue: unit) { saved.angle = angle; didEvaluate = false }
            case ("precision", .picked(let digits)): if let number = Int(digits), [2, 6, 10, 14].contains(number) { saved.precision = number }
            case ("default-view", .picked(let name)): if let mode = CalculatorView(rawValue: name), mode != .history { saved.defaultView = mode }
            case ("keep-history", .toggled(let on)): saved.keepHistory = on
            case ("clear-history", .pressed): saved.history = []
            case ("open", .pressed): view = saved.defaultView; keypadView = view == .scientific ? .scientific : .basic; return .openPage
            default: break
            }
            return nil
        }
        if event.surface == Surface.shortcut {
            if event.control == "open", event.action == .pressed { view = .typing; return .openPage }
            return nil
        }
        if event.control == "expression", event.surface == Surface.notchPage {
            if let screen = event.screen, !["basic", "scientific", "typing"].contains(screen) { return nil }
            switch event.action {
            case .edited(let text), .ended(let text):
                guard text.utf8.count <= Arithmetic.maximumLength else { notice = "Keep expressions under 512 bytes."; return nil }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if expression != trimmed { expression = trimmed; didEvaluate = false }
            case .pressed: evaluate()
            default: break
            }
            return nil
        }
        guard event.action == .pressed else { return nil }
        let control = event.control
        if control.hasPrefix("key:") { key(String(control.dropFirst(4))); return nil }
        if control.hasPrefix("unary:") { applyUnary(String(control.dropFirst(6))); return nil }
        switch control {
        case "open": view = saved.defaultView; keypadView = view == .scientific ? .scientific : .basic; return .openPage
        case "basic", "digits", "view-basic": view = .basic; keypadView = .basic
        case "scientific", "view-scientific": view = .scientific; keypadView = .scientific
        case "typing", "view-typing": view = .typing
        case "show-history": view = view == .history ? keypadView : .history
        case PageScreen.backControl: view = keypadView
        case "pin": pinned.toggle(); return .holdOpen(pinned)
        case "random": expression = NumberText.copied(Double.random(in: 0..<1)); didEvaluate = false
        case "second": second.toggle()
        case "angle": saved.angle = saved.angle == .degrees ? .radians : .degrees; didEvaluate = false
        case "clear": expression = ""; didEvaluate = false
        case "backspace": if !expression.isEmpty { expression.removeLast() }; didEvaluate = false
        case "equals": evaluate()
        case "copy", "result":
            guard let value else { notice = "Complete the expression first."; return nil }
            return .copy(NumberText.copied(value))
        case "memory-clear": memory = 0
        case "exponent": append("e")
        case "memory-recall":
            if let last = expression.last, "+-−*×/÷^(".contains(last) { append("(" + NumberText.copied(memory) + ")") }
            else { expression = NumberText.copied(memory); didEvaluate = false }
        case "memory-add", "memory-subtract":
            guard let value else { notice = "Complete the expression first."; return nil }
            let next = memory + (control == "memory-add" ? value : -value)
            if next.isFinite { memory = next; notice = "Memory updated." } else { notice = "Memory is out of range." }
        case "history":
            if let entry = saved.history.first(where: { $0.id == event.item }) {
                expression = entry.expression; saved.angle = entry.angle; didEvaluate = false; view = .typing
            }
        default: break
        }
        return nil
    }

    private mutating func applyUnary(_ name: String) {
        let allowed = ["square", "cube", "sqrt", "cbrt", "sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", "tanh", "asinh", "acosh", "atanh", "ln", "log", "log2", "exp", "pow10", "pow2", "abs"]
        guard allowed.contains(name) else { return }
        let next: String
        if !expression.isEmpty, value != nil {
            let input = "(" + expression + ")"
            next = name == "square" ? input + "^2" : name == "cube" ? input + "^3" : name + input
        } else { next = name == "square" ? expression + "^2" : name == "cube" ? expression + "^3" : expression + name + "(" }
        guard next.utf8.count <= Arithmetic.maximumLength else { notice = "Expression is too long."; return }
        expression = next; didEvaluate = false
    }

    private mutating func key(_ key: String) {
        switch key {
        case "=": evaluate()
        case "AC": expression = ""; didEvaluate = false
        case "⌫": if !expression.isEmpty { expression.removeLast() }; didEvaluate = false
        case "±": negateEntry()
        case "1/x":
            guard let value else { notice = "Complete the expression first."; return }
            expression = "1/(" + NumberText.copied(value) + ")"; didEvaluate = false
        case "e": append("(e)")
        default:
            guard key.utf8.count <= 16, key.allSatisfy({ $0.isASCII || "π√×÷−".contains($0) }) else { return }
            append(key)
        }
    }
    private mutating func negateEntry() {
        if !didEvaluate, let range = expression.range(of: #"(?:[0-9][0-9,]*(?:\.[0-9]*)?|\.[0-9]+)(?:e[+-]?[0-9]+)?$"#, options: .regularExpression) {
            let prefix = expression[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let previous = prefix.dropLast().last
            if let last = prefix.last, "-−".contains(last),
               previous == nil || "+-−*×/÷^(".contains(previous!),
               let minus = expression[..<range.lowerBound].lastIndex(where: { "-−".contains($0) }) {
                expression.remove(at: minus)
            } else { expression.insert("-", at: range.lowerBound) }
        } else if let value { expression = NumberText.copied(-value) }
        else { append("-") }
        didEvaluate = false
    }
    private mutating func append(_ token: String) {
        var next = expression
        if didEvaluate {
            if let first = token.first, "+-−*×/÷^%!".contains(first), let value { next = "(" + NumberText.copied(value) + ")" }
            else { next = "" }
        }
        guard (next + token).utf8.count <= Arithmetic.maximumLength else { notice = "Expression is too long."; return }
        expression = next + token
        didEvaluate = false
    }
    private mutating func evaluate() {
        guard !expression.isEmpty, let value else { notice = "Check the expression or number range."; return }
        if saved.keepHistory, !didEvaluate {
            saved.history.insert(Calculation(id: UUID().uuidString, expression: expression, result: value, angle: saved.angle), at: 0)
            saved.history = Array(saved.history.prefix(50))
        }
        didEvaluate = true
    }
}
