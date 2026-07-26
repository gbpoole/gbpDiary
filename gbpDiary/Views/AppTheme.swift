import SwiftUI

enum AppTheme {
    enum Kanagawa {
        static let crust = Color(hex: 0x0B0B0F)
        static let mantle = Color(hex: 0x16161D)
        static let base = Color(hex: 0x1F1F28)
        static let surface0 = Color(hex: 0x2A2A37)
        static let surface1 = Color(hex: 0x363645)
        static let surface2 = Color(hex: 0x3E3E51)
        static let overlay0 = Color(hex: 0x49495F)
        static let overlay1 = Color(hex: 0x54546D)
        static let text = Color(hex: 0xDCD7BA)
        static let subtext1 = Color(hex: 0xD4CEAA)
        static let subtext0 = Color(hex: 0xC8C093)
        static let red = Color(hex: 0xFF5D62)
        static let peach = Color(hex: 0xFFA066)
        static let yellow = Color(hex: 0xDCA561)
        static let green = Color(hex: 0x98BB6C)
        static let teal = Color(hex: 0x7AA89F)
        static let sapphire = Color(hex: 0x7FB4CA)
        static let blue = Color(hex: 0x7E9CD8)
        static let mauve = Color(hex: 0x957FB8)
    }

    static let background = Kanagawa.base
    static let sidebarBackground = Kanagawa.mantle
    static let card = Kanagawa.surface0
    static let cardRaised = Kanagawa.surface1
    static let border = Kanagawa.surface2
    static let text = Kanagawa.text
    static let mutedText = Kanagawa.subtext0
    static let accent = Kanagawa.yellow
    static let today = Kanagawa.green
    static let destructive = Kanagawa.red

    static let project = Kanagawa.blue
    static let person = Kanagawa.green
    static let institution = Kanagawa.mauve
    static let duration = Kanagawa.sapphire
    static let tag = Kanagawa.teal
    static let action = Kanagawa.peach
    static let followUp = Kanagawa.peach
    static let completed = Kanagawa.green
    static let started = Kanagawa.blue

    static func interfaceFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Monoid Nerd Font Propo", size: size).weight(weight)
    }

    static func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Hiragino Sans", size: size).weight(weight)
    }

    static func chipBackground(_ color: Color, opacity: Double = 0.16) -> Color {
        color.opacity(opacity)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

struct KanagawaAppBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(AppTheme.bodyFont(size: 13))
            .foregroundStyle(AppTheme.text)
            .background(AppTheme.background)
            .scrollContentBackground(.hidden)
            .preferredColorScheme(.dark)
    }
}

extension View {
    func kanagawaAppBackground() -> some View {
        modifier(KanagawaAppBackground())
    }
}
