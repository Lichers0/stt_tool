import SwiftUI

struct SegmentedPicker<T: Hashable>: View {
    let items: [(label: String, value: T)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = item.value
                    }
                } label: {
                    Text(item.label)
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .fill(selection == item.value
                                      ? Color(nsColor: .controlBackgroundColor)
                                      : Color.clear)
                                .shadow(color: selection == item.value
                                        ? .black.opacity(0.06) : .clear,
                                        radius: 1, y: 1)
                        )
                        .foregroundStyle(selection == item.value ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(DS.Colors.surfaceSubtle.opacity(0.6))
        )
    }
}
