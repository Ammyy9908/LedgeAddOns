import Foundation
import Testing
@testable import CalculatorCore

@Suite struct ArithmeticTests {
    @Test(arguments: [
        ("249 * 12", 2988.0), ("2 + 3 * 4", 14), ("(2 + 3) * 4", 20),
        ("2 ^ 3 ^ 2", 512), ("-2^2", -4), ("2^-3", 0.125),
        ("200 + 10%", 220), ("200 - 10%", 180), ("200 * 10%", 20),
        ("2pi", 2 * Double.pi), ("4(2+3)", 20), ("1e3 + 2.5e-2", 1000.025),
        ("sin(30)", 0.5), ("sin(30)^2", 0.25), ("cos(60)", 0.5), ("asin(0.5)", 30),
        ("sqrt(81)", 9), ("cbrt(-8)", -2), ("log(1000)", 3),
        ("ln(e)", 1), ("log2(8)", 3), ("sinh(0)", 0),
        ("5!", 120), ("0!", 1), ("abs(-4)", 4), ("1,250 / 5", 250),
    ])
    func evaluatesFiniteMath(expression: String, expected: Double) throws {
        let result = try #require(Arithmetic.evaluate(expression))
        #expect(abs(result - expected) < 1e-9)
    }

    @Test func radiansAndDegreesAreExplicit() throws {
        #expect(abs(try #require(Arithmetic.evaluate("sin(pi/2)", angle: .radians)) - 1) < 1e-12)
        #expect(abs(try #require(Arithmetic.evaluate("sin(90)", angle: .degrees)) - 1) < 1e-12)
    }

    @Test(arguments: ["", "2+", "1/0", "sqrt(-1)", "log(0)", "(-1)!", "2.5!", "171!", "2 3", "1,,000", "1,23", "print(1)", "1e", "1.2.3"])
    func rejectsInvalidOrNonFiniteMath(expression: String) {
        #expect(Arithmetic.evaluate(expression) == nil)
    }

    @Test func boundsInputAndRecursion() {
        #expect(Arithmetic.evaluate(String(repeating: "(", count: 100) + "1" + String(repeating: ")", count: 100)) == nil)
        #expect(Arithmetic.evaluate(String(repeating: "1+", count: 2000) + "1") == nil)
    }
}
