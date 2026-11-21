import Foundation
import LedgeKit
import Testing
@testable import DeveloperToolsCore

private func event(_ id: String, _ action: SurfaceEvent.Action = .pressed, item: String? = nil) -> SurfaceEvent {
    .init(surface: Surface.notchPage, control: id, action: action, item: item)
}

@Test func editsClearStaleResultsAndCopyOnlyRunsOnExplicitRequest() {
    var model = DeveloperToolsModel()
    #expect(model.handle(event("input", .edited("Hello"))) == nil)
    #expect(model.handle(event("run")) == nil)
    #expect(model.result?.text == "SGVsbG8=")
    #expect(model.handle(event("copy")) == .copy("SGVsbG8="))
    _ = model.handle(event("input", .edited("changed")))
    #expect(model.result == nil)
    #expect(model.handle(event("copy")) == nil)
}

@Test func toolSwitchingModeSwitchingAndClearNeverKeepAStaleResult() {
    var model = DeveloperToolsModel()
    _ = model.handle(event("input", .edited("{}")))
    _ = model.handle(event("tool:json"))
    _ = model.handle(event("run"))
    #expect(model.result != nil)
    _ = model.handle(event("mode:minify"))
    #expect(model.result == nil && model.input == "{}")
    _ = model.handle(event("clear"))
    #expect(model.input.isEmpty && model.result == nil)
}

@Test func allToolsAndResultNavigationHaveWorkingBackActions() throws {
    var model = DeveloperToolsModel()
    _ = model.handle(event("all-tools"))
    try model.page().validate()
    _ = model.handle(event("tools", item: "uuid"))
    #expect(model.tool == .uuid)
    _ = model.handle(event("run"))
    _ = model.handle(event("show-result"))
    #expect(model.screen == .result)
    try model.page().validate()
    _ = model.handle(event(PageScreen.backControl))
    #expect(model.screen == .workspace)
}

@Test func allToolStatesFitLedgesSurfaceLimits() throws {
    for tool in DeveloperTool.allCases {
        var model = DeveloperToolsModel(tool: tool)
        let input = tool == .json ? "{\"app\":\"Ledge\"}" : "Hello, Ledge!"
        _ = model.handle(event("input", .edited(input)))
        _ = model.handle(event("run"))
        try model.page().validate()
        try model.settingsPage().validate()
        try model.widget().validate()
        try AddOnShortcut.validate(model.shortcuts)
        _ = model.handle(event("show-result"))
        try model.page().validate()
    }
}

@Test func oversizeInputAndInvalidEventsNeverReachCopyOrExport() {
    var model = DeveloperToolsModel()
    _ = model.handle(event("input", .edited(String(repeating: "x", count: 8193))))
    _ = model.handle(event("run"))
    #expect(model.result == nil && model.notice != nil)
    #expect(model.handle(event("export-qr")) == nil)
    #expect(model.handle(event("tool:unknown")) == nil)
    #expect(model.handle(.init(surface: Surface.settingsPage, control: "run", action: .pressed)) == nil)
}

@Test func everyToolModeAndNavigationPathStaysValid() throws {
    for tool in DeveloperTool.allCases {
        for operation in tool.operations {
            var model = DeveloperToolsModel(tool: tool)
            _ = model.handle(event("mode:\(operation.id)"))
            let input: String
            switch tool {
            case .base64: input = operation.id == "decode" ? "SGVsbG8=" : "Hello"
            case .json: input = "{\"items\":[1,2],\"empty\":{}}"
            case .jwt: input = "eyJhbGciOiJub25lIn0.eyJzdWIiOiIxMjMifQ."
            default: input = "Hello"
            }
            _ = model.handle(event("input", .edited(input)))
            _ = model.handle(event("run"))
            #expect(model.result != nil)
            try model.page().validate()
            _ = model.handle(event("show-result"))
            try model.page().validate()
            _ = model.handle(event(PageScreen.backControl))
            #expect(model.screen == .workspace)
            _ = model.handle(event("choose-mode"))
            try model.page().validate()
            _ = model.handle(event(PageScreen.backControl))
            _ = model.handle(event("all-tools"))
            try model.page().validate()
            _ = model.handle(event("tools", item: tool.rawValue))
            #expect(model.screen == .workspace && model.result == nil)
        }
    }
}

@Test func editedFullResultsCopyWhatIsVisibleAndRejectOversizeEdits() {
    var model = DeveloperToolsModel(tool: .uuid)
    _ = model.handle(event("run"))
    _ = model.handle(event("show-result"))
    _ = model.handle(event("result", .ended("Edited result")))
    #expect(model.handle(event("copy")) == .copy("Edited result"))
    _ = model.handle(event("result", .ended(String(repeating: "x", count: 40_001))))
    #expect(model.result == nil && model.notice != nil)
    #expect(model.handle(event("copy")) == nil)
}

@Test func qrExportRequiresAnExplicitPressAndDoesNotReadClipboard() {
    var model = DeveloperToolsModel(tool: .qr)
    #expect(model.handle(event("input", .edited("https://www.tryledge.app/"))) == nil)
    #expect(model.handle(event("run")) == nil)
    guard case .exportPNG(let png) = model.handle(event("export-qr")) else { Issue.record("Expected explicit PNG export"); return }
    #expect(png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
    #expect(model.handle(event("copy")) == .copy("https://www.tryledge.app/"))
    _ = model.handle(event("input", .edited("changed")))
    #expect(model.handle(event("export-qr")) == nil)
}

@Test func staleScreenEventsCannotChangeTheCurrentWorkspace() {
    var model = DeveloperToolsModel()
    _ = model.handle(event("all-tools"))
    _ = model.handle(.init(surface: Surface.notchPage, control: "input", action: .edited("stale"), screen: "workspace"))
    #expect(model.input.isEmpty)
    #expect(model.handle(.init(surface: Surface.shortcut, control: "open-tools", action: .pressed)) == .openPage)
}

@Test func uuidGenerationDoesNotDependOnHiddenTextInput() {
    var model = DeveloperToolsModel()
    _ = model.handle(event("input", .edited(String(repeating: "x", count: 8193))))
    _ = model.handle(event("tool:uuid"))
    _ = model.handle(event("run"))
    #expect(UUID(uuidString: model.result?.text ?? "") != nil)
}
