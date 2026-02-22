import SwiftUI

struct ActionButton: View {
    enum Style { case ghost, outline, filled }

    let icon: String
    var text: String? = nil
    var style: Style = .ghost
    var destructive: Bool = false
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                if let text {
                    Text(text)
                        .font(.system(size: 11))
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, text != nil ? 8 : 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
    }

    private var foregroundColor: Color {
        if destructive && isHovering { return DS.Colors.destructive }
        switch style {
        case .ghost:
            return isHovering ? .primary : .secondary
        case .outline:
            return .primary
        case .filled:
            return .white
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .ghost:
            return isHovering ? DS.Colors.surfaceHover : .clear
        case .outline:
            return isHovering ? DS.Colors.surfaceHover : .clear
        case .filled:
            return DS.Colors.primary
        }
    }
}
