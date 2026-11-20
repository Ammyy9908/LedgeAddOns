import Foundation
import LedgeKit
import Testing
@testable import CalculatorCore

private func press(_ control: String, item: String? = nil) -> SurfaceEvent {
    SurfaceEvent(surface: Surface.notchPage, control: control, action: .pressed, item: item)
}
private func type(_ text: String) -> SurfaceEvent {
    SurfaceEvent(surface: Surface.notchPage, control: "expression", action: .edited(text), screen: "typing")
}

@Test func livePreviewDoesNotSaveUntilEvaluated() {
    var model = CalculatorModel()
    _ = model.handle(type("249 * 12"))
    #expect(model.value == 2988)
    #expect(model.saved.history.isEmpty)
    _ = model.handle(press("equals"))
    #expect(model.saved.history.count == 1)
    #expect(model.saved.history.first?.expression == "249 * 12")
    _ = model.handle(press("equals"))
    #expect(model.saved.history.count == 1)
}

@Test func keypadChainsResultsAndStartsNewNumbers() {
    var model = CalculatorModel()
    for key in ["2", "+", "3", "="] { _ = model.handle(press("key:" + key)) }
    #expect(model.value == 5)
    for key in ["*", "4", "="] { _ = model.handle(press("key:" + key)) }
    #expect(model.value == 20)
    _ = model.handle(press("key:8"))
    #expect(model.expression == "8")
}

@Test func signChangesTheCurrentEntryAndMemoryRecallReplacesIt() {
    var model = CalculatorModel()
    for key in ["2", "+", "3", "±"] { _ = model.handle(press("key:" + key)) }
    #expect(model.value == -1)
    _ = model.handle(press("key:±"))
    #expect(model.value == 5)
    _ = model.handle(press("memory-add"))
    _ = model.handle(press("memory-recall"))
    #expect(model.value == 5)
}

@Test func memoryAndHistoryRestoreKeepPrecision() throws {
    var model = CalculatorModel()
    _ = model.handle(type("1/3"))
    _ = model.handle(press("equals"))
    let value = try #require(model.value)
    _ = model.handle(press("memory-add"))
    _ = model.handle(press("clear"))
    _ = model.handle(press("memory-recall"))
    #expect(model.value == value)
    let entry = try #require(model.saved.history.first)
    _ = model.handle(press("history", item: entry.id))
    #expect(model.expression == "1/3")
    #expect(model.handle(press("copy")) == .copy(NumberText.copied(value)))
}

@Test func invalidResultsNeverEnterHistoryOrMemory() {
    var model = CalculatorModel()
    _ = model.handle(type("1/0"))
    _ = model.handle(press("equals"))
    _ = model.handle(press("memory-add"))
    #expect(model.value == nil)
    #expect(model.saved.history.isEmpty)
    #expect(model.memory == 0)
    #expect(model.handle(press("copy")) == nil)
}

@Test func historyRestoresItsOriginalAngleUnitAfterSerialization() throws {
    var model = CalculatorModel()
    _ = model.handle(type("sin(30)")); _ = model.handle(press("equals"))
    let data = try JSONEncoder().encode(model.saved)
    model = CalculatorModel(saved: try JSONDecoder().decode(CalculatorState.self, from: data))
    _ = model.handle(press("angle"))
    _ = model.handle(press("history", item: try #require(model.saved.history.first).id))
    #expect(model.saved.angle == .degrees)
    #expect(abs(try #require(model.value) - 0.5) < 1e-12)
}

@Test func changingAngleCanCommitADifferentResult() {
    var model = CalculatorModel()
    _ = model.handle(type("sin(30)")); _ = model.handle(press("equals"))
    _ = model.handle(press("angle")); _ = model.handle(press("equals"))
    #expect(model.saved.history.count == 2)
    #expect(model.saved.history.first?.angle == .radians)
}

@Test func preferencesAndHistoryAreBoundedAndSurviveRestart() {
    var model = CalculatorModel()
    _ = model.handle(SurfaceEvent(surface: Surface.settingsPage, control: "angle", action: .picked("radians")))
    for number in 1...60 { _ = model.handle(type("\(number)+1")); _ = model.handle(press("equals")) }
    #expect(model.saved.history.count == 50)
    let restored = CalculatorModel(saved: model.saved)
    #expect(restored.saved.angle == .radians)
    #expect(restored.saved.history == model.saved.history)
    _ = model.handle(SurfaceEvent(surface: Surface.settingsPage, control: "keep-history", action: .toggled(false)))
    _ = model.handle(type("999+1")); _ = model.handle(press("equals"))
    #expect(model.saved.history.count == 50)
}

@Test func everyViewAndWidgetPassesLedgesLimits() throws {
    var model = CalculatorModel()
    _ = model.handle(type("sin(30) + 2pi")); _ = model.handle(press("equals"))
    for control in ["basic", "scientific", "second", "typing", "show-history"] {
        _ = model.handle(press(control))
        try model.page().validate()
    }
    try model.widget().validate()
    try model.settingsPage().validate()
}

@Test func scientificKeepsDigitsAndFunctionsInOneGrid() throws {
    var model = CalculatorModel()
    _ = model.handle(press("scientific"))
    #expect(model.page().preferredWidth == 720)
    func find(_ node: PageNode) -> [PageButton] {
        switch node {
        case .buttonGrid(let columns, _, let buttons):
            #expect(columns == 10)
            return buttons
        case .vstack(_, let children), .hstack(_, let children): return children.flatMap(find)
        default: return []
        }
    }
    let buttons = find(model.page().screen.content)
    #expect(buttons.count == 50)
    #expect(buttons.contains { $0.id == "key:7" })
    #expect(buttons.contains { $0.id == "unary:sin" })
    #expect(buttons.first { $0.id == "key:÷" }?.role == .accent)
    try model.page().validate()
}

@Test func inlineInputReturnAndPinWorkWithoutASeparateTypingPage() {
    var model = CalculatorModel()
    _ = model.handle(SurfaceEvent(surface: Surface.notchPage, control: "expression", action: .edited("249 * 12"), screen: "basic"))
    _ = model.handle(press("expression"))
    #expect(model.saved.history.first?.result == 2988)
    #expect(model.handle(press("pin")) == .holdOpen(true))
    #expect(model.handle(press("pin")) == .holdOpen(false))
    _ = model.handle(press("clear"))
    _ = model.handle(type("30"))
    _ = model.handle(press("unary:sin"))
    #expect(abs((model.value ?? 0) - 0.5) < 1e-12)
}

@Test func endingInlineEditingAfterReturnDoesNotSaveTwice() {
    var model = CalculatorModel()
    _ = model.handle(type("2+3"))
    _ = model.handle(press("expression"))
    _ = model.handle(SurfaceEvent(surface: Surface.notchPage, control: "expression", action: .ended("2+3"), screen: "basic"))
    _ = model.handle(press("equals"))
    #expect(model.saved.history.count == 1)
}

@Test func basicKeyPositionsFollowTheNativeMacCalculator() throws {
    let page = CalculatorModel().page()
    func buttons(_ node: PageNode) -> [PageButton] {
        switch node {
        case .buttonGrid(_, _, let buttons): buttons
        case .vstack(_, let children), .hstack(_, let children): children.flatMap(buttons)
        default: []
        }
    }
    let keys = buttons(page.screen.content).map(\.id)
    #expect(Array(keys.prefix(4)) == ["key:⌫", "key:AC", "key:%", "key:÷"])
    #expect(Array(keys.suffix(4)) == ["key:±", "key:0", "key:.", "key:="])
}

@Test(arguments: [false, true], [false, true])
func allViewPathsPreserveTheCalculationAndSelectedKeypad(scientific: Bool, second: Bool) throws {
    var saved = CalculatorState()
    saved.defaultView = scientific ? .scientific : .basic
    var model = CalculatorModel(saved: saved)
    _ = model.handle(type("sin(30) + 2pi")); _ = model.handle(press("equals"))
    let result = try #require(model.value)
    if second { _ = model.handle(press("second")) }
    let entry = try #require(model.saved.history.first)
    func verify(_ model: CalculatorModel) throws {
        try model.page().validate()
        try model.widget().validate()
        try model.settingsPage().validate()
        #expect(model.value == result)
        #expect(model.keypadView == (scientific ? .scientific : .basic))
        #expect(model.second == second)
        #expect(model.page().preferredWidth == (scientific ? 720 : nil))
    }
    // Settings first-open, History back/toggle, row restore, shortcut, and widget reopen.
    _ = model.handle(SurfaceEvent(surface: Surface.settingsPage, control: "open", action: .pressed))
    try verify(model)
    for _ in 0..<10 {
        _ = model.handle(press("show-history")); try verify(model)
        _ = model.handle(press("back")); try verify(model)
        _ = model.handle(press("show-history")); try verify(model)
        _ = model.handle(press("show-history")); try verify(model)
        _ = model.handle(press("show-history"))
        _ = model.handle(press("history", item: entry.id)); try verify(model)
        _ = model.handle(SurfaceEvent(surface: Surface.shortcut, control: "open", action: .pressed)); try verify(model)
        _ = model.handle(SurfaceEvent(surface: Surface.widget, control: "open", action: .pressed)); try verify(model)
    }
    #expect(model.saved.history.count == 1)
}
