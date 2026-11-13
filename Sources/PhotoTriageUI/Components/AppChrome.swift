import SwiftUI

public enum AppChromeTokens {
    public static let heroCornerRadius: CGFloat = 28
    public static let panelCornerRadius: CGFloat = 24
    public static let cardCornerRadius: CGFloat = 20
    public static let rowCornerRadius: CGFloat = 16
    public static let sectionSpacing: CGFloat = 20
    public static let panelPadding: CGFloat = 20
    public static let compactPadding: CGFloat = 14
    public static let borderOpacity: Double = 0.08
    public static let elevatedShadow = Color.black.opacity(0.34)
    public static let restingShadow = Color.black.opacity(0.24)
}

public enum AppTheme {
    public static let backgroundBase = Color(red: 0.018, green: 0.021, blue: 0.030)
    public static let backgroundSecondary = Color(red: 0.045, green: 0.049, blue: 0.062)
    public static let backgroundTertiary = Color(red: 0.090, green: 0.082, blue: 0.070)

    public static let heroStart = Color(red: 0.050, green: 0.055, blue: 0.070)
    public static let heroMiddle = Color(red: 0.080, green: 0.074, blue: 0.070)
    public static let heroEnd = Color(red: 0.835, green: 0.776, blue: 0.558)

    public static let panelFill = Color(red: 0.082, green: 0.085, blue: 0.098).opacity(0.94)
    public static let panelTopHighlight = Color.white.opacity(0.11)
    public static let cardFill = Color(red: 0.108, green: 0.112, blue: 0.126).opacity(0.92)
    public static let subtleFill = Color(red: 0.135, green: 0.136, blue: 0.145).opacity(0.72)
    public static let rowFill = Color.white.opacity(0.08)

    public static let borderSoft = Color.white.opacity(0.105)
    public static let borderStrong = Color.white.opacity(0.155)
    public static let borderAccent = heroEnd.opacity(0.52)

    public static let textPrimary = Color.white.opacity(0.94)
    public static let textSecondary = Color.white.opacity(0.68)
    public static let textMuted = Color.white.opacity(0.48)
    public static let textOnAccent = Color(red: 0.058, green: 0.066, blue: 0.072)
    public static let textOnDark = Color.white.opacity(0.94)
    public static let textOnDarkSecondary = Color.white.opacity(0.72)

    public static let success = Color(red: 0.145, green: 0.630, blue: 0.355)
    public static let warning = Color(red: 0.945, green: 0.505, blue: 0.185)
    public static let danger = Color(red: 0.840, green: 0.230, blue: 0.230)
    public static let accentLime = Color(red: 0.835, green: 0.776, blue: 0.558)
    public static let accentPeach = Color(red: 0.640, green: 0.520, blue: 0.395)

    public static let glow = accentLime.opacity(0.22)
}

public enum AppSemanticStatus {
    case neutral
    case selected
    case focused
    case pending
    case keep
    case reject
    case loading
    case danger

    public var tint: Color {
        switch self {
        case .neutral:
            AppTheme.textSecondary
        case .selected, .focused:
            AppTheme.accentLime
        case .pending:
            AppTheme.warning
        case .keep:
            AppTheme.success
        case .reject, .danger:
            AppTheme.danger
        case .loading:
            AppTheme.accentPeach
        }
    }

    public var foreground: Color {
        switch self {
        case .selected, .focused:
            AppTheme.textOnAccent
        case .neutral:
            AppTheme.textSecondary
        default:
            tint
        }
    }

    public var background: Color {
        switch self {
        case .neutral:
            AppTheme.rowFill
        default:
            tint.opacity(0.15)
        }
    }

    public var border: Color {
        switch self {
        case .neutral:
            AppTheme.borderSoft
        default:
            tint.opacity(0.34)
        }
    }
}

public struct AppWorkspaceBackdrop: View {
    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.backgroundBase,
                    AppTheme.backgroundSecondary,
                    Color.black.opacity(0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [AppTheme.heroEnd.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 30,
                endRadius: 520
            )

            RadialGradient(
                colors: [AppTheme.accentPeach.opacity(0.16), .clear],
                center: .bottomLeading,
                startRadius: 40,
                endRadius: 480
            )

            LinearGradient(
                colors: [Color.white.opacity(0.05), .clear, Color.black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

public enum AppSurfaceKind {
    case hero
    case panel
    case card
    case subtle
}

public extension View {
    func appSurface(_ kind: AppSurfaceKind = .panel) -> some View {
        modifier(AppSurfaceStyle(kind: kind))
    }
}

private struct AppSurfaceStyle: ViewModifier {
    let kind: AppSurfaceKind

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if kind == .hero {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.accentLime.opacity(0.18),
                                    .clear,
                                    AppTheme.accentPeach.opacity(0.12)
                                ],
                                startPoint: .topTrailing,
                                endPoint: .bottomLeading
                            )
                        )
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .hero:
            AnyShapeStyle(
                LinearGradient(
                    colors: [
                        AppTheme.heroStart,
                        AppTheme.heroMiddle,
                        Color(red: 0.128, green: 0.165, blue: 0.145)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .panel:
            AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.045),
                        AppTheme.panelFill,
                        AppTheme.backgroundSecondary.opacity(0.86)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .card:
            AnyShapeStyle(
                LinearGradient(
                    colors: [Color.white.opacity(0.035), AppTheme.cardFill],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .subtle:
            AnyShapeStyle(
                LinearGradient(
                    colors: [Color.white.opacity(0.025), AppTheme.subtleFill],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var cornerRadius: CGFloat {
        switch kind {
        case .hero:
            AppChromeTokens.heroCornerRadius
        case .panel:
            AppChromeTokens.panelCornerRadius
        case .card, .subtle:
            AppChromeTokens.cardCornerRadius
        }
    }

    private var padding: CGFloat {
        switch kind {
        case .hero, .panel:
            AppChromeTokens.panelPadding
        case .card, .subtle:
            AppChromeTokens.compactPadding
        }
    }

    private var shadowColor: Color {
        switch kind {
        case .hero:
            Color(red: 0.06, green: 0.08, blue: 0.07).opacity(0.28)
        case .panel:
            AppChromeTokens.elevatedShadow
        case .card:
            AppChromeTokens.restingShadow
        case .subtle:
            .clear
        }
    }

    private var shadowRadius: CGFloat {
        switch kind {
        case .hero:
            28
        case .panel:
            22
        case .card:
            14
        case .subtle:
            0
        }
    }

    private var shadowY: CGFloat {
        switch kind {
        case .hero:
            16
        case .panel:
            12
        case .card:
            8
        case .subtle:
            0
        }
    }
}

public struct AppStatPill: View {
    let title: String
    let value: String
    let tint: Color

    public init(title: String, value: String, tint: Color = .primary) {
        self.title = title
        self.value = value
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textMuted)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.18), AppTheme.cardFill],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.clear, lineWidth: 0)
        }
    }
}

public struct AppCapsuleLabel: View {
    let text: String
    let tint: Color

    public init(_ text: String, tint: Color = .primary) {
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(backgroundColor, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            }
    }

    private var foregroundColor: Color {
        tint == .primary ? AppTheme.textPrimary : tint.opacity(0.96)
    }

    private var backgroundColor: Color {
        tint == .primary ? AppTheme.rowFill : tint.opacity(0.16)
    }

    private var borderColor: Color {
        tint == .primary ? AppTheme.borderSoft : tint.opacity(0.30)
    }
}

public struct AppStatusPill: View {
    let title: String
    let status: AppSemanticStatus
    let systemImage: String?

    public init(_ title: String, status: AppSemanticStatus = .neutral, systemImage: String? = nil) {
        self.title = title
        self.status = status
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(status.foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(status.background, in: Capsule())
        .overlay {
            Capsule()
                .stroke(status.border, lineWidth: 1)
        }
    }
}

public extension View {
    func appFocusRing(isActive: Bool, status: AppSemanticStatus = .focused, cornerRadius: CGFloat = AppChromeTokens.rowCornerRadius) -> some View {
        overlay {
            if isActive {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(status.tint.opacity(0.74), lineWidth: 2)
            }
        }
    }
}

public struct AppSectionTitle: View {
    let title: String
    let subtitle: String?

    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}
