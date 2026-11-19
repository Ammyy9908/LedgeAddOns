import Foundation
import Testing
@testable import LauncherCore

@Suite struct CalculatorTests {
    @Test func doesSumsInOrder() {
        #expect(Calculator.evaluate("2 + 3 * 4") == 14)
        #expect(Calculator.evaluate("(2 + 3) * 4") == 20)
        #expect(Calculator.evaluate("2 ^ 3 ^ 2") == 512)
        #expect(Calculator.evaluate("10 ÷ 4") == 2.5)
        #expect(Calculator.evaluate("-3 × -2") == 6)
        #expect(Calculator.evaluate("1,250 / 5") == 250)
        #expect(Calculator.evaluate("sqrt 16 + 1") == 5)
    }

    @Test func percentagesWorkLikeAPocketCalculator() {
        #expect(Calculator.evaluate("80 + 15%") == 92)
        #expect(Calculator.evaluate("200 - 10%") == 180)
        #expect(Calculator.evaluate("50%") == 0.5)
    }

    @Test func refusesWhatItDoesntUnderstand() {
        #expect(Calculator.evaluate("2 +") == nil)
        #expect(Calculator.evaluate("hello") == nil)
        #expect(Calculator.evaluate("(1 + 2") == nil)
        #expect(Calculator.evaluate("1 / 0") == nil)
    }

    @Test func onlyAnswersSums() {
        #expect(Calculator.looksLikeMath("12 * 4"))
        #expect(Calculator.looksLikeMath("sqrt(2)"))
        #expect(!Calculator.looksLikeMath("1984"))
        #expect(!Calculator.looksLikeMath("safari"))
        #expect(!Calculator.looksLikeMath("1password"))
    }

    @Test func numbersReadWell() {
        #expect(NumberText.shown(1234567.5) == "1,234,567.5")
        #expect(NumberText.copied(1234567.5) == "1234567.5")
        #expect(NumberText.shown(1.0 / 3) == "0.3333333333")
    }
}

@Suite struct AnswerTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-25T09:00:00Z")!

    @Test func tipsAndPercentages() {
        let tip = Launcher.answers("15% tip on 80").first
        #expect(tip?.title == "12")
        #expect(tip?.subtitle == "15% tip on 80 · total 92")
        #expect(Launcher.answers("20% of 150").first?.title == "30")
    }

    @Test func convertsUnits() {
        #expect(Launcher.answers("10 km in miles").first?.title == "6.2137119224 mi")
        #expect(Launcher.answers("212 f to c").first?.title == "100 °C")
        #expect(Launcher.answers("2 gb in mb").first?.copy == "2000")
        #expect(Units.convert("5 kg in miles") == nil)
    }

    @Test func showsATimeSomewhereElse() {
        let answer = TimeZones.answer("3pm london in nyc", now: now, here: TimeZone(identifier: "Asia/Kolkata")!)
        #expect(answer?.time == "11:00 AM")  // London is back on GMT, New York not yet
        #expect(answer?.detail == "New York · Sun, Oct 25 · UTC−4 · 3:00 PM in London")
        #expect(TimeZones.answer("3pm in nyc", now: now, here: TimeZone(identifier: "Asia/Kolkata")!)?.detail
                == "New York · Sun, Oct 25 · UTC−4 · 3:00 PM here")
        #expect(TimeZones.answer("3pm est", now: now, here: TimeZone(identifier: "UTC")!)?.time == "7:00 PM")  // "est" is New York time, daylight saving included
        #expect(TimeZones.answer("now in sydney", now: now)?.time == "8:00 PM")
        #expect(TimeZones.answer("time in tokyo", now: now)?.time == "6:00 PM")
        #expect(TimeZones.answer("9:30 in delhi", now: now, here: TimeZone(identifier: "UTC")!)?.time == "3:00 PM")
        #expect(TimeZones.answer("3pm nowhere in nyc", now: now) == nil)
    }

    @Test func leavesWordsAlone() {
        #expect(Launcher.answers("safari").isEmpty)
        #expect(Launcher.answers("notes").isEmpty)
    }
}

@Suite struct MatchingTests {
    private func app(_ name: String) -> Entry { Entry(LauncherResult(id: name, title: name, kind: "Application")) }

    @Test func ranksTheClosestNameFirst() {
        let apps = ["Notes", "Notion", "Keynote", "Visual Studio Code", "System Settings"].map(app)
        #expect(Launcher.search("not", apps: apps, settings: []).map(\.title) == ["Notes", "Notion", "Keynote"])
        #expect(Launcher.search("vsc", apps: apps, settings: []).first?.title == "Visual Studio Code")
        #expect(Launcher.search("studio code", apps: apps, settings: []).first?.title == "Visual Studio Code")
    }

    @Test func keywordsAndAccentsFindThings() {
        let wifi = Entry(LauncherResult(id: "w", title: "Wi\u{2011}Fi", kind: "Settings"), keywords: ["WiFi"])
        #expect(Launcher.search("wifi", apps: [], settings: [wifi]).first?.title == "Wi\u{2011}Fi")
        #expect(Launcher.search("wi-fi", apps: [], settings: [wifi]).first?.title == "Wi\u{2011}Fi")
        #expect(Launcher.score("Café", query: "cafe") == 100)
    }

    @Test func anAnswerComesBeforeApps() {
        let results = Launcher.search("2+2", apps: [app("2Do")], settings: [])
        #expect(results.first?.kind == "Calculator")
    }

    @Test func webSearchIsEncoded() {
        #expect(Launcher.webSearch("a&b c")?.open == "https://www.google.com/search?q=a%26b%20c")
    }
}
