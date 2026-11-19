import Foundation

/// An AI service the launcher can ask, with the person's own key. One type for every service: what differs is the
/// shape of its API (`Format`), where it lives and which model it uses by default. Any service that speaks one of
/// these shapes works, so an OpenAI-compatible one (OpenRouter, Groq, a local Ollama) is just a base URL.
public struct Assistant: Sendable, Equatable {
    public enum Format: String, Sendable { case anthropic, openAI, gemini }

    public var id: String
    public var name: String
    public var format: Format
    public var baseURL: String
    public var defaultModel: String
    /// A local server may need no key.
    public var needsKey: Bool

    public static let claude = Assistant(id: "claude", name: "Claude", format: .anthropic,
                                         baseURL: "https://api.anthropic.com", defaultModel: "claude-opus-5-5", needsKey: true)
    public static let openAI = Assistant(id: "openai", name: "ChatGPT", format: .openAI,
                                         baseURL: "https://api.openai.com/v1", defaultModel: "gpt-5-mini", needsKey: true)
    public static let gemini = Assistant(id: "gemini", name: "Gemini", format: .gemini,
                                         baseURL: "https://generativelanguage.googleapis.com/v1beta", defaultModel: "gemini-flash-latest", needsKey: true)
    /// Any server with OpenAI's chat completions API, at `baseURL` (up to and including `/v1`).
    public static func compatible(baseURL: String) -> Assistant {
        Assistant(id: "custom", name: URL(string: baseURL)?.host ?? "Custom", format: .openAI,
                  baseURL: baseURL, defaultModel: "", needsKey: false)
    }
    public static let builtIn = [claude, openAI, gemini]

    static let instructions = "You answer questions typed into a search bar on a Mac. Answer directly and briefly, "
        + "in plain text; use a short list only when it helps. No headings."

    /// The request that asks `question`. Throws when the address or model can't be used safely.
    public func request(_ question: String, key: String, model: String) throws -> URLRequest {
        let model = model.isEmpty ? defaultModel : model
        guard !model.isEmpty, model.allSatisfy({ $0.isLetter || $0.isNumber || "-._:/".contains($0) }) else {
            throw AssistantError("Choose a model for \(name) in Settings.")
        }
        guard let base = URL(string: baseURL), let host = base.host,
              base.scheme == "https" || (base.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            // A key must never travel unencrypted to another machine.
            throw AssistantError("The address must start with https:// (or http:// on this Mac).")
        }
        guard !needsKey || !key.isEmpty else { throw AssistantError("Add your \(name) key in Settings.") }
        var body: [String: Any]
        var request: URLRequest
        switch format {
        case .anthropic:
            request = URLRequest(url: base.appendingPathComponent("v1/messages"))
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
            // If the model declines, the API asks another one in the same call.
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body = ["model": model, "max_tokens": 16000, "system": Self.instructions, "fallbacks": "default",
                    "output_config": ["effort": "low"],
                    "messages": [["role": "user", "content": question]]]
        case .openAI:
            request = URLRequest(url: base.appendingPathComponent("chat/completions"))
            if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            body = ["model": model, "messages": [["role": "system", "content": Self.instructions], ["role": "user", "content": question]]]
        case .gemini:
            request = URLRequest(url: base.appendingPathComponent("models/\(model):generateContent"))
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            body = ["systemInstruction": ["parts": [["text": Self.instructions]]],
                    "contents": [["role": "user", "parts": [["text": question]]]]]
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The answer's text from a successful reply.
    public func answer(from data: Data) throws -> String {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        var text: String?
        switch format {
        case .anthropic:
            if json?["stop_reason"] as? String == "refusal" { throw AssistantError("\(name) declined to answer that.") }
            text = (json?["content"] as? [[String: Any]])?.filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }.joined()
        case .openAI:
            text = (((json?["choices"] as? [[String: Any]])?.first?["message"]) as? [String: Any])?["content"] as? String
        case .gemini:
            let parts = (((json?["candidates"] as? [[String: Any]])?.first?["content"]) as? [String: Any])?["parts"] as? [[String: Any]]
            text = parts?.compactMap { $0["text"] as? String }.joined()
        }
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw AssistantError("\(name) sent an empty answer.")
        }
        return text
    }

    /// What to tell the person when the service answers with an error status. Never the body, which can echo the
    /// request.
    public func failure(status: Int) -> AssistantError {
        switch status {
        case 401, 403: AssistantError("\(name) didn't accept the key. Check it in Settings.")
        case 404: AssistantError("\(name) doesn't know that model. Check it in Settings.")
        case 429: AssistantError("\(name) says you're over your rate limit or out of credit.")
        case 500...: AssistantError("\(name) is having trouble. Try again in a moment.")
        default: AssistantError("\(name) couldn't answer (error \(status)).")
        }
    }
}

/// A failure whose message is safe to show.
public struct AssistantError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}
