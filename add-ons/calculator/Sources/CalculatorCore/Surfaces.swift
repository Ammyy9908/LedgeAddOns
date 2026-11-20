import LedgeKit
import Foundation

extension CalculatorModel {
    public func page() -> NotchPage {
        // One header action fits beside the camera even at Compact width.
        let actions: [PageAction] = view == .history ? [] : [PageAction("show-history", symbol: "clock.arrow.circlepath", label: "Calculation history")]
        let modes = row([("view-basic", "Basic"), ("view-scientific", "Scientific"), ("view-typing", "Type")])
        let content: PageNode
        switch view {
        case .history:
            content = saved.history.isEmpty
                ? .empty(symbol: "clock", title: "No calculations yet", detail: "Press equals to keep a result here.")
                : .list(id: "history", rows: saved.history.map { ListRow($0.id, title: String($0.expression.prefix(80)), subtitle: "= " + NumberText.shown($0.result, precision: saved.precision) + ($0.angle == .degrees ? " · DEG" : " · RAD")) })
        case .typing:
            content = .vstack(spacing: 8, children: [
                modes,
                .editor(id: "expression", text: expression, placeholder: "249 * 12 or sin(30) + 2pi", autofocus: true),
                .button(id: "result", title: resultText, symbol: "doc.on.doc"),
                .text(notice ?? "Preview · " + (saved.angle == .degrees ? "Degrees" : "Radians"), style: .caption),
                row([("clear", "Clear"), ("equals", "Evaluate"), ("copy", "Copy")]),
            ])
        case .basic, .scientific:
            var children: [PageNode] = [
                modes,
                .text(expression.isEmpty ? "Enter a calculation" : String(expression.suffix(32)), style: .caption),
                .button(id: "result", title: resultText, symbol: "doc.on.doc"),
            ]
            var keys: [[(String, String)]] = []
            if view == .basic {
                keys = [["AC", "±", "%", "÷"], ["7", "8", "9", "×"], ["4", "5", "6", "−"], ["1", "2", "3", "+"], ["0", ".", "⌫", "="]].map { $0.map { ("key:" + $0, $0) } }
            } else {
                keys.append([("second", second ? "1st" : "2nd"), ("angle", saved.angle == .degrees ? "DEG" : "RAD"), ("key:(", "("), ("key:)", ")")])
                let functions = second
                    ? [["asin", "acos", "atan", "abs"], ["sinh", "cosh", "tanh", "log2"], ["asinh", "acosh", "atanh", "cbrt"]]
                    : [["sin", "cos", "tan", "sqrt"], ["ln", "log", "exp", "abs"]]
                for names in functions { keys.append(names.map { ("key:" + $0 + "(", $0) }) }
                if !second { keys.append([("key:π", "π"), ("key:e", "e"), ("exponent", "EE"), ("key:^", "xʸ")]) }
                keys.append([("memory-clear", "mc"), ("memory-add", "m+"), ("memory-subtract", "m−"), ("memory-recall", "mr")])
                keys.append([("digits", "Digits"), ("key:!", "x!"), ("key:1/x", "1/x"), ("equals", "=")])
            }
            children.append(keypad(keys))
            if let notice { children.append(.text(notice, style: .caption)) }
            content = .vstack(spacing: 6, children: children)
        }
        return NotchPage(title: "Calculator", symbol: "plus.forwardslash.minus", size: .large,
                         screen: PageScreen(view.rawValue, depth: view == .history ? 1 : 0, title: view == .history ? nil : "Calc", back: view == .history, actions: actions, content: content))
    }

    private func row(_ keys: [(String, String)]) -> PageNode {
        .hstack(spacing: 8, children: keys.map { .button(id: $0.0, title: $0.1, symbol: nil) })
    }

    /// Shared columns keep every key aligned; independent expanding row spacers do not.
    private func keypad(_ rows: [[(String, String)]]) -> PageNode {
        .hstack(spacing: 12, children: (0..<4).map { column in
            .vstack(spacing: 6, children: rows.map { .button(id: $0[column].0, title: $0[column].1, symbol: nil) })
        })
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
                .picker("default-view", "Default view", options: [.init("basic", "Basic"), .init("scientific", "Scientific"), .init("typing", "Typing")], selected: saved.defaultView.rawValue),
                .picker("angle", "Angles", options: [.init("degrees", "Degrees"), .init("radians", "Radians")], selected: saved.angle.rawValue),
                .picker("precision", "Decimal places", options: [2, 6, 10, 14].map { .init(String($0), String($0)) }, selected: String(saved.precision)),
            ]),
            SettingsSection("history", title: "History", footer: "Only evaluated expressions are saved, on this Mac. Memory is cleared when the add-on stops.", rows: [
                .toggle("keep-history", "Keep history", isOn: saved.keepHistory),
                .value("history-count", "Saved calculations", String(saved.history.count)),
                .button("clear-history", "Clear history", destructive: true,
                        confirm: .init("Clear calculation history?", message: "Removes the saved calculations on this Mac.", confirmTitle: "Clear history")),
                .note("limits", "Uses double-precision numbers. No currency conversion or arbitrary precision. Type expressions in the typing view; use Evaluate to save one."),
            ]),
        ], keywords: ["math", "scientific", "memory", "history", "trigonometry"])
    }
}
