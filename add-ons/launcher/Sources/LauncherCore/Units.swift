import Foundation

/// "5 km in miles", "72 f to c", "2 gb in mb": a number, a unit, "in" or "to", and a unit of the same kind.
public enum Units {
    public struct Conversion: Equatable, Sendable {
        public var value: Double
        public var from: String
        public var to: String
        public var result: Double
    }

    public static func convert(_ text: String) -> Conversion? {
        let pattern = #"^\s*(-?[\d.,]+)\s*([a-z°/µ"' .]+?)\s+(?:in|to|into|as)\s+([a-z°/µ"' .]+?)\s*$"#
        guard let match = text.lowercased().firstMatch(pattern), match.count == 4,
              let value = Double(match[1].replacingOccurrences(of: ",", with: "")),
              let from = units[match[2].trimmingCharacters(in: .whitespaces)],
              let to = units[match[3].trimmingCharacters(in: .whitespaces)],
              type(of: from.unit) == type(of: to.unit) else { return nil }
        let result = Measurement(value: value, unit: from.unit).converted(to: to.unit).value
        return Conversion(value: value, from: from.name, to: to.name, result: result)
    }

    private struct Named {
        var name: String
        var unit: Dimension
    }

    /// Spellings people type, to a unit and how it reads back.
    private static let units: [String: Named] = {
        var table: [String: Named] = [:]
        func add(_ unit: Dimension, _ name: String, _ spellings: String...) {
            for spelling in spellings { table[spelling] = Named(name: name, unit: unit) }
        }
        add(UnitLength.millimeters, "mm", "mm", "millimeter", "millimeters", "millimetre", "millimetres")
        add(UnitLength.centimeters, "cm", "cm", "centimeter", "centimeters", "centimetre", "centimetres")
        add(UnitLength.meters, "m", "m", "meter", "meters", "metre", "metres")
        add(UnitLength.kilometers, "km", "km", "kilometer", "kilometers", "kilometre", "kilometres", "kms")
        add(UnitLength.inches, "in", "inch", "inches", "\"")
        add(UnitLength.feet, "ft", "ft", "foot", "feet", "'")
        add(UnitLength.yards, "yd", "yd", "yard", "yards")
        add(UnitLength.miles, "mi", "mi", "mile", "miles")
        add(UnitLength.nauticalMiles, "nmi", "nmi", "nautical mile", "nautical miles")
        add(UnitMass.milligrams, "mg", "mg", "milligram", "milligrams")
        add(UnitMass.grams, "g", "g", "gram", "grams")
        add(UnitMass.kilograms, "kg", "kg", "kgs", "kilo", "kilos", "kilogram", "kilograms")
        add(UnitMass.metricTons, "t", "tonne", "tonnes")
        add(UnitMass.ounces, "oz", "oz", "ounce", "ounces")
        add(UnitMass.pounds, "lb", "lb", "lbs", "pound", "pounds")
        add(UnitMass.stones, "st", "st", "stone", "stones")
        add(UnitTemperature.celsius, "°C", "c", "°c", "celsius", "centigrade")
        add(UnitTemperature.fahrenheit, "°F", "f", "°f", "fahrenheit")
        add(UnitTemperature.kelvin, "K", "k", "kelvin")
        add(UnitVolume.milliliters, "ml", "ml", "milliliter", "milliliters", "millilitre", "millilitres")
        add(UnitVolume.liters, "l", "l", "liter", "liters", "litre", "litres")
        add(UnitVolume.cups, "cups", "cup", "cups")
        add(UnitVolume.fluidOunces, "fl oz", "fl oz", "floz", "fluid ounce", "fluid ounces")
        add(UnitVolume.gallons, "gal", "gal", "gallon", "gallons")
        add(UnitVolume.teaspoons, "tsp", "tsp", "teaspoon", "teaspoons")
        add(UnitVolume.tablespoons, "tbsp", "tbsp", "tablespoon", "tablespoons")
        add(UnitSpeed.kilometersPerHour, "km/h", "km/h", "kph", "kmh")
        add(UnitSpeed.milesPerHour, "mph", "mph", "mi/h")
        add(UnitSpeed.metersPerSecond, "m/s", "m/s", "mps")
        add(UnitSpeed.knots, "kn", "kn", "knot", "knots")
        add(UnitInformationStorage.bytes, "B", "b", "byte", "bytes")
        add(UnitInformationStorage.kilobytes, "KB", "kb", "kilobyte", "kilobytes")
        add(UnitInformationStorage.megabytes, "MB", "mb", "megabyte", "megabytes")
        add(UnitInformationStorage.gigabytes, "GB", "gb", "gigabyte", "gigabytes")
        add(UnitInformationStorage.terabytes, "TB", "tb", "terabyte", "terabytes")
        add(UnitDuration.seconds, "s", "s", "sec", "secs", "second", "seconds")
        add(UnitDuration.minutes, "min", "min", "mins", "minute", "minutes")
        add(UnitDuration.hours, "h", "h", "hr", "hrs", "hour", "hours")
        add(UnitArea.squareMeters, "m²", "m2", "m²", "sqm", "square meters", "square metres")
        add(UnitArea.squareFeet, "ft²", "ft2", "ft²", "sqft", "square feet")
        add(UnitArea.acres, "acres", "acre", "acres")
        add(UnitArea.hectares, "ha", "ha", "hectare", "hectares")
        return table
    }()
}

extension String {
    /// The first match of `pattern` and its groups, empty strings for groups that didn't take part.
    func firstMatch(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: self).map { String(self[$0]) } ?? "" }
    }
}
