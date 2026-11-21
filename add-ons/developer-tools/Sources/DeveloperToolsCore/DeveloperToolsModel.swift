import Foundation
import LedgeKit

/// Ephemeral workspace. Only explicit Copy and To shelf presses produce host effects.
public struct DeveloperToolsModel: Sendable {
    public enum Screen: String, Sendable { case workspace, tools, operations, result }
    public enum Effect: Sendable, Equatable { case openPage, copy(String), exportPNG(Data) }
    public private(set) var tool: DeveloperTool
    public private(set) var operation: String
    public private(set) var input = ""
    public private(set) var result: ToolResult?
    public var notice: String?
    public private(set) var screen: Screen = .workspace

    public init(tool: DeveloperTool = .base64) {
        self.tool = tool
        self.operation = tool.operations[0].id
    }

    public var shortcuts: [AddOnShortcut] { [.init("open-tools", title: "Open developer tools", key: "D")] }

    public mutating func handle(_ event: SurfaceEvent) -> Effect? {
        if [Surface.settingsPage, Surface.widget, Surface.shortcut].contains(event.surface) {
            return event.control == "open-tools" && event.action == .pressed ? .openPage : nil
        }
        guard event.surface == Surface.notchPage,
              event.screen == nil || event.screen == screen.rawValue else { return nil }
        switch (event.control, event.action) {
        case ("input", .edited(let text)), ("input", .ended(let text)):
            guard text != input else { return nil }
            result = nil
            if text.count > 50_000 { input = ""; notice = "Input is limited to 8 KB. Paste a shorter passage." }
            else { input = text; notice = nil }
        case ("result", .edited(let text)), ("result", .ended(let text)):
            guard screen == .result, result != nil, result?.image == nil else { return nil }
            guard text.utf8.count <= 40_000 else { result = nil; notice = "Result exceeds 40 KB. Run the tool again with a smaller input."; return nil }
            result?.text = text
            notice = nil
        case (PageScreen.backControl, .pressed): screen = .workspace
        case ("all-tools", .pressed): screen = .tools
        case ("choose-mode", .pressed): screen = .operations
        case ("show-result", .pressed): if result != nil { screen = .result }
        case ("run", .pressed):
            result = nil
            do { result = try ToolEngine.run(tool, operation: operation, input: tool == .uuid ? "" : input); notice = nil }
            catch { notice = (error as? ToolError)?.description ?? "This input could not be processed." }
        case ("clear", .pressed): input = ""; result = nil; notice = nil
        case ("copy", .pressed):
            if let text = result?.text, !text.isEmpty { return .copy(text) }
        case ("export-qr", .pressed):
            if tool == .qr, let image = result?.image { return .exportPNG(image) }
        case (let id, .pressed):
            let selected = id == "tools" ? event.item : (id.hasPrefix("tool:") ? String(id.dropFirst(5)) : nil)
            if let selected, let tool = DeveloperTool(rawValue: selected) {
                self.tool = tool; operation = tool.operations[0].id
                result = nil; notice = nil; screen = .workspace
            } else {
                let mode = id == "modes" ? event.item : (id.hasPrefix("mode:") ? String(id.dropFirst(5)) : nil)
                if let mode, tool.operations.contains(where: { $0.id == mode }) {
                    operation = mode; result = nil; notice = nil; screen = .workspace
                }
            }
        default: break
        }
        return nil
    }

    public func page() -> NotchPage {
        let content: PageNode
        switch screen {
        case .tools:
            content = .list(id: "tools", rows: DeveloperTool.allCases.map {
                ListRow($0.rawValue, title: $0.title, subtitle: $0.detail, symbol: $0.symbol)
            })
        case .operations:
            content = .list(id: "modes", rows: tool.operations.map { ListRow($0.id, title: $0.title, symbol: operation == $0.id ? "checkmark" : nil) })
        case .result:
            if let image = result?.image {
                content = .vstack(spacing: 8, children: [
                    .image(image, size: 128, motion: nil),
                    .buttonGrid(columns: 2, rowHeight: 28, buttons: [.init("copy", title: "Copy text"), .init("export-qr", title: "To shelf", role: .accent)]),
                    .text(notice ?? "PNG with a quiet zone for scanning.", style: .caption),
                ])
            } else {
                content = .vstack(spacing: 6, children: [
                    .editor(id: "result", text: result?.text ?? "", placeholder: "Result", autofocus: false),
                    .hstack(spacing: 8, children: [.text(notice ?? "Result · editable", style: .caption), .spacer, .control(.init("copy", title: "Copy", role: .accent))]),
                ])
            }
        case .workspace: content = workspace()
        }
        return NotchPage(title: "Dev Tools", symbol: "curlybraces", size: .large,
            screen: PageScreen(screen.rawValue, depth: screen == .workspace ? 0 : 1, title: screen == .tools ? "All tools" : screen == .result ? "Result" : nil,
                back: screen != .workspace, actions: screen == .workspace ? [PageAction("clear", symbol: "trash", label: "Clear workspace")] : [], content: content))
    }

    private func workspace() -> PageNode {
        let modes: [PageNode] = tool == .hash
            ? [.control(.init("choose-mode", title: tool.operations.first(where: { $0.id == operation })?.title ?? "SHA-256"))]
            : tool.operations.count > 1 ? tool.operations.map { .control(.init("mode:\($0.id)", title: $0.title, role: operation == $0.id ? .selected : .secondary)) } : []
        var children: [PageNode] = [
            .hstack(spacing: 4, children: [.text(tool.title, style: .title), .spacer] + modes),
            .buttonGrid(columns: 4, rowHeight: 26, buttons: [DeveloperTool.base64, .json, .hash].map {
                .init("tool:\($0.rawValue)", title: $0.title, role: tool == $0 ? .selected : .secondary)
            } + [.init("all-tools", title: "All", role: .secondary, accessibilityLabel: "All tools")]),
        ]
        if tool != .uuid {
            children.append(.editor(id: "input", text: input, placeholder: tool == .json ? "Paste JSON" : tool == .jwt ? "Paste a JWT" : "Type or paste text", autofocus: false))
        } else {
            children.append(.text("Random version 4 UUID. Generated on this Mac.", style: .secondary))
            children.append(.spacer)
        }
        if let result {
            if let image = result.image {
                children.append(.hstack(spacing: 8, children: [.image(image, size: 64, motion: nil), .text("QR code ready", style: .secondary), .spacer,
                    .control(.init("export-qr", title: "To shelf", role: .accent))]))
            } else {
                let preview = result.text.replacingOccurrences(of: "\n", with: " ")
                children.append(.text(String(preview.prefix(80)) + (preview.count > 80 ? "…" : ""), style: .monospaced))
            }
        }
        if let message = notice ?? result?.note { children.append(.text(String(message.prefix(240)), style: .caption)) }
        var actions = [PageButton("run", title: tool.operations.first(where: { $0.id == operation })?.title ?? "Run", role: .accent)]
        if result != nil {
            actions.append(.init("copy", title: tool == .qr ? "Copy text" : "Copy"))
            actions.append(.init("show-result", title: tool == .qr ? "Preview" : "Full result", role: .secondary))
        }
        children.append(.buttonGrid(columns: actions.count, rowHeight: 28, buttons: actions))
        return .vstack(spacing: 6, children: children)
    }

    public func widget() -> Widget {
        Widget("tools", title: "Dev Tools", symbol: "curlybraces", content: .vstack(spacing: 6, children: [
            .text("7 local tools. Nothing uploaded.", style: .secondary), .button(id: "open-tools", title: "Open tools", symbol: "arrow.up.right"),
        ]))
    }

    public func settingsPage() -> SettingsPage {
        SettingsPage([
            SettingsSection("workspace", title: "Developer Tools", footer: notice, rows: [.button("open-tools", "Open tools", detail: "Local text utilities in the notch")]),
            SettingsSection("tools", title: "Included tools", rows: DeveloperTool.allCases.map { .note("info:\($0.rawValue)", "\($0.title): \($0.detail).") }),
            SettingsSection("privacy", title: "Privacy and limits", rows: [
                .note("local", "Input and results stay in memory. They are not saved, logged or sent over the network. Clear the workspace or turn off the add-on to discard them."),
                .note("limits", "Input: 8 KB. QR: 1,800 bytes. Results: 40 KB. Copy writes only when pressed; To shelf creates a PNG only when pressed."),
                .note("jwt", "JWT decoding does not verify signatures. SHA-1 and MD5 are legacy checksums, not password or security tools."),
            ]),
        ], keywords: ["base64", "json", "hash", "uuid", "jwt", "url", "qr", "developer"])
    }
}
