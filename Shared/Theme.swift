import SwiftUI

// MARK: - Thèmes cyberpunk

struct TaffeTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let tagline: String
    let background: Color
    let surface: Color
    let primary: Color
    let secondary: Color
    let text: Color
    let dim: Color
    let alert: Color

    static func == (lhs: TaffeTheme, rhs: TaffeTheme) -> Bool {
        lhs.id == rhs.id
    }

    static let neon = TaffeTheme(
        id: "neon",
        name: "NÉON//VILLE",
        tagline: "Jaune électrique, nuit sans fin",
        background: Color(hex: 0x0B0B12),
        surface: Color(hex: 0x16161F),
        primary: Color(hex: 0xFCEE0A),
        secondary: Color(hex: 0x00F0FF),
        text: Color(hex: 0xF5F5F5),
        dim: Color(hex: 0x8C8CA0),
        alert: Color(hex: 0xFF003C)
    )

    static let corpo = TaffeTheme(
        id: "corpo",
        name: "CORPO//ROUGE",
        tagline: "Tour noire, sang-froid",
        background: Color(hex: 0x07070A),
        surface: Color(hex: 0x131318),
        primary: Color(hex: 0xFF1F3D),
        secondary: Color(hex: 0xE6E6EA),
        text: Color(hex: 0xF4F4F6),
        dim: Color(hex: 0x8A8A94),
        alert: Color(hex: 0xFFB800)
    )

    static let netrunner = TaffeTheme(
        id: "netrunner",
        name: "NETRUNNER",
        tagline: "Plongée dans le réseau",
        background: Color(hex: 0x020805),
        surface: Color(hex: 0x08160F),
        primary: Color(hex: 0x00FF9C),
        secondary: Color(hex: 0x00B8FF),
        text: Color(hex: 0xD8FFE9),
        dim: Color(hex: 0x5E8C72),
        alert: Color(hex: 0xFF3355)
    )

    static let synth = TaffeTheme(
        id: "synth",
        name: "CHROME//ROSE",
        tagline: "Synthwave sous la pluie",
        background: Color(hex: 0x0D0221),
        surface: Color(hex: 0x1A0B33),
        primary: Color(hex: 0xFF2A6D),
        secondary: Color(hex: 0x05D9E8),
        text: Color(hex: 0xF7E8FF),
        dim: Color(hex: 0x9A82B8),
        alert: Color(hex: 0xFFD300)
    )

    static let badlands = TaffeTheme(
        id: "badlands",
        name: "BADLANDS",
        tagline: "Poussière et chrome",
        background: Color(hex: 0x0E0A06),
        surface: Color(hex: 0x1C140C),
        primary: Color(hex: 0xFF8A00),
        secondary: Color(hex: 0xFFD9A0),
        text: Color(hex: 0xFFF1E0),
        dim: Color(hex: 0xA08A70),
        alert: Color(hex: 0xFF3B3B)
    )

    static let ice = TaffeTheme(
        id: "ice",
        name: "GLACE//ICE",
        tagline: "Contre-mesures actives",
        background: Color(hex: 0x050A10),
        surface: Color(hex: 0x0C1822),
        primary: Color(hex: 0x7DF9FF),
        secondary: Color(hex: 0xFFFFFF),
        text: Color(hex: 0xE8FBFF),
        dim: Color(hex: 0x6D8A99),
        alert: Color(hex: 0xFF4D6D)
    )

    static let all: [TaffeTheme] = [neon, corpo, netrunner, synth, badlands, ice]

    static func named(_ id: String?) -> TaffeTheme {
        all.first { $0.id == id } ?? neon
    }

    static var current: TaffeTheme {
        named(TaffeShared.defaults.string(forKey: SharedKeys.theme))
    }
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: TaffeTheme = .neon
}

extension EnvironmentValues {
    var theme: TaffeTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Forme à coins coupés

struct CutCornerShape: Shape {
    var cut: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let c = min(cut, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        path.closeSubpath()
        return path
    }
}
