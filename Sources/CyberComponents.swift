import SwiftUI
import UIKit

// MARK: - Fond

struct Scanlines: View {
    var color: Color
    var opacity: Double = 0.05
    var spacing: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                let line = Path(CGRect(x: 0, y: y, width: size.width, height: 1))
                context.fill(line, with: .color(color.opacity(opacity)))
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

struct CyberBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.background
            LinearGradient(colors: [theme.primary.opacity(0.12), .clear],
                           startPoint: .top,
                           endPoint: .center)
            Scanlines(color: theme.primary, opacity: 0.04)
        }
        .ignoresSafeArea()
    }
}

struct CyberScreen: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(CyberBackground())
            .toolbarBackground(theme.surface, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar, .tabBar)
    }
}

// MARK: - En-tête

struct CyberHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(subtitle.uppercased())
                .font(.mono(11, .semibold))
                .foregroundStyle(theme.secondary)
                .tracking(2)
            Text(title)
                .font(.mono(34, .black))
                .foregroundStyle(theme.text)
                .shadow(color: theme.primary.opacity(0.7), radius: 8)
            Rectangle()
                .fill(LinearGradient(colors: [theme.primary, theme.primary.opacity(0)],
                                     startPoint: .leading,
                                     endPoint: .trailing))
                .frame(height: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

// MARK: - Panneau

struct CyberPanel<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let accent: Color?
    let content: Content

    init(_ title: String, accent: Color? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        let color = accent ?? theme.primary
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(color)
                    .frame(width: 3, height: 12)
                Text("// " + title.uppercased())
                    .font(.mono(12, .bold))
                    .foregroundStyle(color)
                    .tracking(1.5)
                Spacer()
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CutCornerShape(cut: 16).fill(theme.surface))
        .overlay(CutCornerShape(cut: 16).stroke(color.opacity(0.55), lineWidth: 1))
    }
}

// MARK: - Boutons

struct CyberButtonStyle: ButtonStyle {
    var color: Color
    var filled: Bool = false
    var textColor: Color = .black

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mono(14, .heavy))
            .tracking(1)
            .foregroundStyle(filled ? textColor : color)
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(CutCornerShape(cut: 10).fill(filled ? color : color.opacity(0.08)))
            .overlay(CutCornerShape(cut: 10).stroke(color, lineWidth: filled ? 0 : 1))
            .shadow(color: color.opacity(filled ? 0.6 : 0), radius: 10)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

// MARK: - Barres

struct NeonBar: View {
    let value: Double
    let color: Color
    var marker: Double? = nil
    var markerColor: Color = .orange
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let clamped = CGFloat(min(max(value, 0), 1))
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(color.opacity(0.12))
                Rectangle()
                    .fill(color)
                    .frame(width: geo.size.width * clamped)
                    .shadow(color: color.opacity(0.8), radius: 6)
                if let marker {
                    let markerPosition = CGFloat(min(max(marker, 0), 1))
                    Rectangle()
                        .fill(markerColor)
                        .frame(width: 3)
                        .offset(x: geo.size.width * markerPosition - 1.5)
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Petits éléments

struct StatTile: View {
    @Environment(\.theme) private var theme
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.mono(10, .bold))
                .foregroundStyle(theme.dim)
                .tracking(1.5)
            Text(value)
                .font(.mono(30, .black))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.6), radius: 6)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CutCornerShape(cut: 12).fill(theme.surface))
        .overlay(CutCornerShape(cut: 12).stroke(color.opacity(0.4), lineWidth: 1))
    }
}

struct InfoLine: View {
    @Environment(\.theme) private var theme
    let key: String
    let value: String

    var body: some View {
        HStack {
            Text(key)
                .font(.mono(11, .bold))
                .foregroundStyle(theme.dim)
            Spacer()
            Text(value)
                .font(.mono(11, .bold))
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct SettingRow: View {
    @Environment(\.theme) private var theme
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.mono(12, .bold))
                .foregroundStyle(theme.text)
            Spacer()
            Text(value)
                .font(.mono(12))
                .foregroundStyle(theme.dim)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.primary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Partage

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
