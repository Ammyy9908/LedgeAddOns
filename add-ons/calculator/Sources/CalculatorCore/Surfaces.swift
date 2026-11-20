import LedgeKit
import Foundation

extension CalculatorModel {
    public func page() -> NotchPage {
        let scientific = keypadView == .scientific
        let toolbar: PageNode = .hstack(spacing: 6, children: [
            .control(PageButton("view-basic", title: "Basic", role: scientific ? .normal : .selected)),
            .control(PageButton("view-scientific", title: "Scientific", role: scientific ? .selected : .normal)),
            .spacer,
            .control(PageButton("show-history", title: "", role: view == .history ? .selected : .normal, symbol: "clock.arrow.circlepath", accessibilityLabel: "Calculation history")),
            .control(PageButton("pin", title: "", role: pinned ? .selected : .normal, symbol: pinned ? "pin.fill" : "pin", accessibilityLabel: pinned ? "Unpin calculator" : "Pin calculator")),
            .control(PageButton("copy", title: "", symbol: "doc.on.doc", accessibilityLabel: "Copy result")),
        ])
        var children = [toolbar]
        if view == .history {
            children.append(saved.history.isEmpty
                ? .empty(symbol: "clock", title: "No calculations yet", detail: "Press equals to keep a result here.")
                : .list(id: "history", rows: saved.history.map { ListRow($0.id, title: String($0.expression.prefix(80)) + ($0.angle == .degrees ? " · DEG" : " · RAD"), subtitle: NumberText.shown($0.result, precision: saved.precision), emphasizesSubtitle: true) }))
        } else {
            children.append(.readout(PageReadout("expression", expression: expression, value: resultText, copyControl: "result", autofocus: view == .typing, status: notice)))
            children.append(.buttonGrid(columns: scientific ? 10 : 4, rowHeight: 30, buttons: scientific ? scientificKeys() : basicKeys()))
        }
        if view == .history, let notice { children.append(.text(notice, style: .caption)) }
        return NotchPage(title: "Calculator", symbol: "plus.forwardslash.minus", size: .large, preferredWidth: scientific ? 720 : nil,
                         screen: PageScreen(view.rawValue, depth: view == .history ? 1 : 0, back: view == .history, content: .vstack(spacing: 4, children: children)))
    }

    private func key(_ title: String, token: String? = nil, role: PageButton.Role = .normal, label: String? = nil) -> PageButton {
        PageButton("key:" + (token ?? title), title: title, role: role, accessibilityLabel: label)
    }

    private func basicKeys() -> [PageButton] { numericRows().flatMap { $0 } }

    private func numericRows() -> [[PageButton]] {
        [[key("⌫", role: .secondary, label: "Delete last character"), key("AC", role: .secondary, label: "All clear"), key("%", role: .secondary, label: "Percent"), key("÷", role: .accent, label: "Divide")],
         [key("7"), key("8"), key("9"), key("×", role: .accent, label: "Multiply")],
         [key("4"), key("5"), key("6"), key("−", role: .accent, label: "Subtract")],
         [key("1"), key("2"), key("3"), key("+", role: .accent, label: "Add")],
         [key("±", label: "Change sign"), key("0"), key("."), key("=", role: .accent, label: "Equals")]]
    }

    private func scientificKeys() -> [PageButton] {
        func control(_ id: String, _ title: String, _ label: String? = nil) -> PageButton {
            PageButton(id, title: title, accessibilityLabel: label)
        }
        func unary(_ name: String, _ title: String, _ label: String? = nil) -> PageButton {
            control("unary:" + name, title, label)
        }
        let angle = saved.angle == .degrees ? "DEG" : "RAD"
        let left: [[PageButton]] = [
            [key("("), key(")"), control("memory-clear", "mc", "Clear memory"), control("memory-add", "m+", "Add to memory"), control("memory-subtract", "m−", "Subtract from memory"), control("memory-recall", "mr", "Recall memory")],
            [PageButton("second", title: "2ⁿᵈ", role: second ? .selected : .normal, accessibilityLabel: "Second function bank"), unary("square", "x²", "Square"), unary("cube", "x³", "Cube"), key("xʸ", token: "^", label: "Power"), unary(second ? "ln" : "exp", second ? "ln x" : "eˣ"), unary(second ? "pow2" : "pow10", second ? "2ˣ" : "10ˣ")],
            [key("1/x", label: "Reciprocal"), unary("sqrt", "²√x", "Square root"), unary("cbrt", "³√x", "Cube root"), key("ʸ√x", token: "^(1/", label: "Nth root; enter the degree then close the parenthesis"), unary(second ? "exp" : "ln", second ? "eˣ" : "ln"), unary(second ? "log2" : "log", second ? "log₂" : "log₁₀")],
            [key("x!", token: "!", label: "Factorial"), unary(second ? "asin" : "sin", second ? "sin⁻¹" : "sin"), unary(second ? "acos" : "cos", second ? "cos⁻¹" : "cos"), unary(second ? "atan" : "tan", second ? "tan⁻¹" : "tan"), key("e"), control("exponent", "EE", "Scientific exponent")],
            [control("random", "Rand", "Random number"), unary(second ? "asinh" : "sinh", second ? "sinh⁻¹" : "sinh"), unary(second ? "acosh" : "cosh", second ? "cosh⁻¹" : "cosh"), unary(second ? "atanh" : "tanh", second ? "tanh⁻¹" : "tanh"), key("π"), control("angle", angle, "Angle unit: " + angle)],
        ]
        return zip(left, numericRows()).flatMap { $0 + $1 }
    }

    public func widget() -> Widget {
        var parts: [WidgetNode] = [.text(resultText, style: .monospaced), .hstack(spacing: 8, children: [
            .button(id: "open", title: "Open", symbol: nil), .button(id: "copy", title: "Copy", symbol: nil),
        ])]
        if let notice { parts.append(.text(String(notice.prefix(22)), style: .caption)) }
        var compact = parts
        compact[0] = .text(value.map { String(format: "%.6g", $0) } ?? "—", style: .monospaced)
        return Widget("calculator", title: "Calculator", symbol: "plus.forwardslash.minus", content: .vstack(spacing: 6, children: parts),
                      compactContent: .vstack(spacing: 6, children: compact))
    }

    public func settingsPage() -> SettingsPage {
        SettingsPage([
            SettingsSection("calculator", title: "Calculator", rows: [
                .button("open", "Open calculator"),
                .picker("default-view", "Default view", options: [.init("basic", "Basic"), .init("scientific", "Scientific")], selected: saved.defaultView.rawValue),
                .picker("angle", "Angles", options: [.init("degrees", "Degrees"), .init("radians", "Radians")], selected: saved.angle.rawValue),
                .picker("precision", "Decimal places", options: [2, 6, 10, 14].map { .init(String($0), String($0)) }, selected: String(saved.precision)),
            ]),
            SettingsSection("history", title: "History", footer: "Only evaluated expressions are saved, on this Mac. Memory is cleared when the add-on stops.", rows: [
                .toggle("keep-history", "Keep history", isOn: saved.keepHistory),
                .value("history-count", "Saved calculations", String(saved.history.count)),
                .button("clear-history", "Clear history", destructive: true,
                        confirm: .init("Clear calculation history?", message: "Removes the saved calculations on this Mac.", confirmTitle: "Clear history")),
                .note("limits", "Uses double-precision numbers. No currency conversion or arbitrary precision. Click the expression above the result; press Return to save it."),
            ]),
        ], keywords: ["math", "scientific", "memory", "history", "trigonometry"])
    }
}
