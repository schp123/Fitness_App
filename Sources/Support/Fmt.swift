import Foundation
import SwiftUI

enum Fmt {
    static let de = Locale(identifier: "de_DE")

    /// 45 → „45“, 47.5 → „47,5“, 0 → „“
    static func num(_ v: Double, emptyZero: Bool = true) -> String {
        if emptyZero && v == 0 { return "" }
        let f = NumberFormatter()
        f.locale = de
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    static func kg(_ v: Double) -> String { v == 0 ? "–" : "\(num(v)) kg" }

    static func parse(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty else { return nil }
        return Double(t)
    }

    static func volume(_ v: Double) -> String {
        if v >= 10000 { return "\(num((v / 1000 * 10).rounded() / 10)) t" }
        return "\(Int(v.rounded())) kg"
    }

    static func reps(_ min: Int, _ max: Int) -> String {
        if max <= 0 || max == min { return "\(min)" }
        return "\(min)–\(max)"
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    static func minutes(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        if m >= 60 { return "\(m / 60) h \(m % 60) min" }
        return "\(m) min"
    }

    static func rest(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return String(format: "%d:%02d min", seconds / 60, seconds % 60)
    }

    static func day(_ d: Date) -> String { d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(de)) }
    static func dayLong(_ d: Date) -> String { d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(de)) }
    static func short(_ d: Date) -> String { d.formatted(.dateTime.day().month(.twoDigits).locale(de)) }
    static func time(_ d: Date) -> String { d.formatted(.dateTime.hour().minute().locale(de)) }

    static func relative(_ d: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 0
        switch days {
        case 0: return "heute"
        case 1: return "gestern"
        case 2..<7: return "vor \(days) Tagen"
        default: return short(d)
        }
    }

    static let weekdays = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    static let weekdaysLong = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]

    /// 1 = Montag … 7 = Sonntag
    static func isoWeekday(_ d: Date) -> Int {
        let w = Calendar.current.component(.weekday, from: d) // 1 = So
        return w == 1 ? 7 : w - 1
    }
}

extension Calendar {
    static var iso: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.locale = Locale(identifier: "de_DE")
        c.timeZone = .current
        return c
    }
    func startOfWeek(_ d: Date) -> Date {
        dateInterval(of: .weekOfYear, for: d)?.start ?? startOfDay(for: d)
    }
}

/// Zahlenfeld, das während der Eingabe sofort speichert (Komma oder Punkt).
struct DecimalField: View {
    @Binding var value: Double
    var placeholder: String
    var integer: Bool = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(integer ? .numberPad : .decimalPad)
            .multilineTextAlignment(.center)
            .focused($focused)
            .onAppear { text = Fmt.num(value) }
            .onChange(of: text) { _, t in
                if let v = Fmt.parse(t) { if v != value { value = integer ? v.rounded() : v } }
                else if t.isEmpty, value != 0 { value = 0 }
            }
            .onChange(of: value) { _, v in
                if !focused || Fmt.parse(text) != v { if Fmt.parse(text) != v { text = Fmt.num(v) } }
            }
            .onChange(of: focused) { _, f in if f == false { text = Fmt.num(value) } }
    }
}

struct IntField: View {
    @Binding var value: Int
    var placeholder: String
    var body: some View {
        DecimalField(value: Binding(get: { Double(value) }, set: { value = Int($0) }), placeholder: placeholder, integer: true)
    }
}
