import SwiftUI

enum AppButtonKind {
    case primary
    case secondary
    case destructive
    case toolbar
}

enum AppButtonTokens {
    static let cornerRadius: CGFloat = 21
    static let cardCornerRadius: CGFloat = 18
    static let rowCornerRadius: CGFloat = 14
    static let contentHeight: CGFloat = 42
    static let toolbarHeight: CGFloat = 36
    static let horizontalPadding: CGFloat = 16
    static let toolbarHorizontalPadding: CGFloat = 14
    static let borderOpacity: Double = 0.10
    static let pressedScale: CGFloat = 0.985
    static let disabledOpacity: Double = 0.42
}

struct AppButtonStyle: ButtonStyle {
    let kind: AppButtonKind

    func makeBody(configuration: Configuration) -> some View {
        AppButtonBody(configuration: configuration, kind: kind)
    }

    private struct AppButtonBody: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration
        let kind: AppButtonKind
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(font)
                .foregroundStyle(foregroundColor)
                .frame(minHeight: height)
                .padding(.horizontal, horizontalPadding)
                .background(background, in: RoundedRectangle(cornerRadius: AppButtonTokens.cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppButtonTokens.cornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                }
                .appFocusRing(isActive: isHovered && isEnabled, status: focusStatus, cornerRadius: AppButtonTokens.cornerRadius)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: AppButtonTokens.cornerRadius, style: .continuous)
                        .stroke(topHighlight, lineWidth: 1)
                        .mask {
                            LinearGradient(
                                colors: [.white, .white.opacity(0.12), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                }
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
                .opacity(isEnabled ? 1 : AppButtonTokens.disabledOpacity)
                .scaleEffect(configuration.isPressed ? AppButtonTokens.pressedScale : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.16), value: isHovered)
                .onHover { hovering in
                    isHovered = hovering
                }
        }

        private var font: Font {
            switch kind {
            case .toolbar:
                .subheadline.weight(.medium)
            default:
                .subheadline.weight(.semibold)
            }
        }

        private var height: CGFloat {
            kind == .toolbar ? AppButtonTokens.toolbarHeight : AppButtonTokens.contentHeight
        }

        private var horizontalPadding: CGFloat {
            kind == .toolbar ? AppButtonTokens.toolbarHorizontalPadding : AppButtonTokens.horizontalPadding
        }

        private var foregroundColor: Color {
            switch kind {
            case .primary, .secondary:
                AppTheme.textOnAccent
            case .toolbar:
                AppTheme.textPrimary
            case .destructive:
                AppTheme.danger
            }
        }

        private var background: AnyShapeStyle {
            switch kind {
            case .primary:
                AnyShapeStyle(
                    LinearGradient(
                        colors: [
                            AppTheme.accentLime.opacity(configuration.isPressed ? 0.86 : 1),
                            Color(red: 0.760, green: 0.900, blue: 0.205).opacity(isHovered ? 1 : 0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            case .secondary:
                AnyShapeStyle(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(configuration.isPressed ? 0.58 : 0.78),
                            Color.white.opacity(isHovered ? 0.68 : 0.52)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            case .toolbar:
                AnyShapeStyle(
                    LinearGradient(
                        colors: [
                            AppTheme.textPrimary.opacity(configuration.isPressed ? 0.070 : 0.055),
                            AppTheme.textPrimary.opacity(isHovered ? 0.055 : 0.030)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            case .destructive:
                AnyShapeStyle(
                    LinearGradient(
                        colors: [
                            AppTheme.danger.opacity(configuration.isPressed ? 0.22 : 0.28),
                            AppTheme.danger.opacity(isHovered ? 0.14 : 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
        }

        private var borderColor: Color {
            switch kind {
            case .primary:
                AppTheme.textOnAccent.opacity(isHovered ? 0.20 : 0.12)
            case .secondary:
                AppTheme.borderStrong.opacity(isHovered ? 1.0 : 0.75)
            case .toolbar:
                AppTheme.borderSoft.opacity(isHovered ? 1.0 : 0.75)
            case .destructive:
                AppTheme.danger.opacity(isHovered ? 0.48 : 0.32)
            }
        }

        private var borderWidth: CGFloat { 1 }

        private var topHighlight: Color {
            switch kind {
            case .primary:
                Color.white.opacity(0.38)
            case .secondary:
                Color.white.opacity(0.30)
            case .toolbar:
                Color.white.opacity(0.12)
            case .destructive:
                Color.white.opacity(0.10)
            }
        }

        private var shadowColor: Color {
            switch kind {
            case .primary:
                AppTheme.accentLime.opacity(isHovered ? 0.34 : 0.22)
            case .destructive:
                AppTheme.danger.opacity(isHovered ? 0.18 : 0.10)
            case .secondary:
                Color.black.opacity(isHovered ? 0.14 : 0.08)
            case .toolbar:
                Color.black.opacity(isHovered ? 0.10 : 0.05)
            }
        }

        private var shadowRadius: CGFloat {
            switch kind {
            case .primary:
                isHovered ? 20 : 14
            case .toolbar:
                isHovered ? 10 : 6
            case .secondary, .destructive:
                isHovered ? 14 : 10
            }
        }

        private var shadowY: CGFloat {
            switch kind {
            case .primary:
                10
            case .toolbar:
                4
            default:
                6
            }
        }

        private var focusStatus: AppSemanticStatus {
            switch kind {
            case .destructive:
                .danger
            case .primary:
                .selected
            case .secondary, .toolbar:
                .focused
            }
        }
    }
}

struct SidebarRowButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SidebarRowButtonBody(configuration: configuration, isSelected: isSelected)
    }

    private struct SidebarRowButtonBody: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration
        let isSelected: Bool
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background(background, in: RoundedRectangle(cornerRadius: AppButtonTokens.rowCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppButtonTokens.rowCornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: isSelected || isHovered ? 1 : 0)
                }
                .appFocusRing(isActive: isSelected, status: .selected, cornerRadius: AppButtonTokens.rowCornerRadius)
                .shadow(color: shadowColor, radius: isSelected ? 16 : (isHovered ? 10 : 0), y: isSelected ? 8 : 5)
                .opacity(isEnabled ? 1 : AppButtonTokens.disabledOpacity)
                .scaleEffect(configuration.isPressed ? 0.992 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.16), value: isHovered)
                .contentShape(RoundedRectangle(cornerRadius: AppButtonTokens.rowCornerRadius, style: .continuous))
                .onHover { hovering in
                    isHovered = hovering
                }
        }

        private var background: AnyShapeStyle {
            if isSelected {
                return AnyShapeStyle(
                    LinearGradient(
                        colors: [AppTheme.accentLime.opacity(configuration.isPressed ? 0.28 : 0.34), AppTheme.heroMiddle.opacity(isHovered ? 0.24 : 0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }

            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.white.opacity(configuration.isPressed ? 0.090 : 0.070), AppTheme.subtleFill.opacity(isHovered ? 0.92 : 0.74)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        private var borderColor: Color {
            if isSelected {
                return AppTheme.accentLime.opacity(isHovered ? 0.60 : 0.42)
            }
            return Color.clear
        }

        private var shadowColor: Color {
            isSelected ? AppTheme.accentLime.opacity(0.20) : Color.black.opacity(isHovered ? 0.08 : 0)
        }
    }
}

struct SelectionCardButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SelectionCardButtonBody(configuration: configuration, isSelected: isSelected)
    }

    private struct SelectionCardButtonBody: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration
        let isSelected: Bool
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0.035), AppTheme.cardFill],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: AppButtonTokens.cardCornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppButtonTokens.cardCornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                }
                .appFocusRing(isActive: isSelected, status: .selected, cornerRadius: AppButtonTokens.cardCornerRadius)
                .shadow(color: shadowColor, radius: shadowRadius, y: 8)
                .opacity(isEnabled ? 1 : AppButtonTokens.disabledOpacity)
                .scaleEffect(configuration.isPressed ? AppButtonTokens.pressedScale : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.16), value: isHovered)
                .contentShape(RoundedRectangle(cornerRadius: AppButtonTokens.cardCornerRadius, style: .continuous))
                .onHover { hovering in
                    isHovered = hovering
                }
        }

        private var borderColor: Color {
            if isSelected {
                return AppTheme.accentLime.opacity(isHovered ? 0.92 : 0.76)
            }
            return Color.clear
        }

        private var borderWidth: CGFloat {
            isSelected ? 2 : 0
        }

        private var shadowColor: Color {
            if isSelected {
                return AppTheme.accentLime.opacity(isHovered ? 0.22 : 0.14)
            }
            return Color.black.opacity(isHovered ? 0.14 : 0.08)
        }

        private var shadowRadius: CGFloat {
            if isSelected {
                return isHovered ? 22 : 16
            }
            return isHovered ? 14 : 10
        }
    }
}

extension View {
    func appButtonStyle(_ kind: AppButtonKind) -> some View {
        buttonStyle(AppButtonStyle(kind: kind))
    }
}
