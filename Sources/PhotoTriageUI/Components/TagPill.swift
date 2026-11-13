import PhotoTriageCore
import SwiftUI

struct TagPill: View {
    @EnvironmentObject private var state: AppState
    let tag: AppTag

    var body: some View {
        Text(priorityTag.map(state.priorityTagDisplayName) ?? tag.name)
            .font(.caption.weight(priorityTag == nil ? .regular : .semibold))
            .lineLimit(1)
            .help(priorityTag.map(state.priorityTagDisplayName) ?? tag.name)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(border, lineWidth: 1)
            }
    }

    private var priorityTag: PriorityTag? {
        PriorityTag.fromAppTag(tag)
    }

    private var foreground: Color {
        priorityTag.map(Self.foregroundColor(for:)) ?? Color.accentColor
    }

    private var background: Color {
        priorityTag.map { Self.tintColor(for: $0).opacity(0.20) } ?? Color.accentColor.opacity(0.12)
    }

    private var border: Color {
        priorityTag.map { Self.tintColor(for: $0).opacity(0.50) } ?? Color.accentColor.opacity(0.22)
    }

    private static func foregroundColor(for tag: PriorityTag) -> Color {
        switch tag {
        case .p0:
            return Color(red: 1.00, green: 0.64, blue: 0.64)
        case .p1:
            return Color(red: 1.00, green: 0.80, blue: 0.36)
        case .p2:
            return Color(red: 0.62, green: 0.78, blue: 1.00)
        default:
            return Color(red: 0.78, green: 0.84, blue: 0.90)
        }
    }

    static func tintColor(for tag: PriorityTag) -> Color {
        switch tag {
        case .p0:
            return Color(red: 0.92, green: 0.20, blue: 0.22)
        case .p1:
            return Color(red: 0.95, green: 0.58, blue: 0.12)
        case .p2:
            return Color(red: 0.22, green: 0.48, blue: 0.95)
        default:
            return Color(hue: Double((tag.index % 360 * 47) % 360) / 360, saturation: 0.55, brightness: 0.80)
        }
    }
}
