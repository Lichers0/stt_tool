import SwiftUI

struct StatusIndicator: View {
    let state: AppState
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(state.statusColor)
            .frame(width: DS.Layout.statusDotSize, height: DS.Layout.statusDotSize)
            .opacity(isPulsing ? 0.5 : 1.0)
            .onChange(of: state.isRecording, initial: true) { _, recording in
                if recording {
                    withAnimation(DS.pulseRecording) { isPulsing = true }
                } else {
                    withAnimation(.easeOut(duration: 0.15)) { isPulsing = false }
                }
            }
    }
}
