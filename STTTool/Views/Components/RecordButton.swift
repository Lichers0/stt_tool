import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: DS.Layout.smallIconSize))
                Text(isRecording ? "Stop Recording" : "Start Recording")
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: DS.Layout.recordButtonHeight)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xl)
                    .fill(isRecording ? DS.Colors.destructive : DS.Colors.primary)
            )
            .opacity(isHovering && !isDisabled ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        .onHover { hovering in isHovering = hovering }
    }
}
