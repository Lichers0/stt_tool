import SwiftUI

struct StatusBadge: View {
    let text: String
    var foregroundColor: Color = .secondary
    var backgroundColor: Color = Color(nsColor: .quaternarySystemFill)

    var body: some View {
        Text(text)
            .font(DS.Typography.tinyLabel)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .clipShape(Capsule())
    }
}
