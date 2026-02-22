import SwiftUI

struct PermissionCard: View {
    let index: Int
    let icon: String
    let title: String
    let description: String
    let granted: Bool
    var actionLabel: String = "Grant"
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            // Status: checkmark or number — fixed 22x22 for both states
            ZStack {
                if granted {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(.green)
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
                    Text("\(index)")
                        .font(DS.Typography.tinyLabel)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                }

                Text(description)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)

                if !granted, let action {
                    Button(actionLabel, action: action)
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(granted ? DS.Colors.primary.opacity(0.05) : DS.Colors.surfaceSubtle)
        )
    }
}
