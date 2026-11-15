import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    /// Farbe, die sich automatisch an Hell-/Dunkelmodus anpasst.
    static func dynamic(_ light: String, _ dark: String) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

enum Theme {
    // Creme, Beige, Schwarz, dezentes Rosé
    static let bg = Color.dynamic("F6F0E8", "121010")
    static let card = Color.dynamic("FFFCF8", "1D1A19")
    static let beige = Color.dynamic("ECE1D3", "2A2523")
    static let ink = Color.dynamic("1B1716", "F4ECE4")
    static let muted = Color.dynamic("7D7068", "A99D94")
    static let line = Color.dynamic("E6DACB", "332D2A")
    static let rose = Color.dynamic("BF8584", "D8A3A2")
    static let roseSoft = Color.dynamic("F4E3E0", "3A2828")
    static let roseInk = Color.dynamic("8E5554", "F0C4C2")
    static let good = Color.dynamic("6F8A6C", "9BB898")
    static let goodSoft = Color.dynamic("E5ECE1", "243024")
    static let warn = Color.dynamic("B9763F", "E3A574")
    static let warnSoft = Color.dynamic("F6E7D8", "3A2C20")
    static let onInk = Color.dynamic("FFFCF8", "121010")

    static let chart: [Color] = [rose, Color.dynamic("A88F78", "C9B29B"), Color.dynamic("1B1716", "F4ECE4"),
                                 Color.dynamic("6F8A6C", "9BB898"), Color.dynamic("B9763F", "E3A574")]

    static func serif(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif).weight(weight)
    }
}

// MARK: - Bausteine

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line, lineWidth: 0.5))
    }
}

struct SectionTitle: View {
    var text: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(Theme.serif(.title3, .medium)).foregroundStyle(Theme.ink)
            Spacer()
            if let trailing { Text(trailing).font(.footnote).foregroundStyle(Theme.muted) }
        }
    }
}

struct Pill: View {
    var text: String
    var color: Color = Theme.roseSoft
    var ink: Color = Theme.roseInk
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption2.weight(.semibold)) }
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(color, in: Capsule())
        .foregroundStyle(ink)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.ink
    var textColor: Color = Theme.onInk
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(textColor)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.beige.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .foregroundStyle(Theme.ink)
    }
}

struct StatTile: View {
    var value: String
    var label: String
    var icon: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let icon { Image(systemName: icon).font(.footnote).foregroundStyle(Theme.rose) }
            Text(value).font(Theme.serif(.title2, .semibold)).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line, lineWidth: 0.5))
    }
}

struct EmptyHint: View {
    var icon: String
    var title: String
    var text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title).foregroundStyle(Theme.rose)
            Text(title).font(Theme.serif(.headline)).foregroundStyle(Theme.ink)
            Text(text).font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

extension View {
    func screenBackground() -> some View {
        self.scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
