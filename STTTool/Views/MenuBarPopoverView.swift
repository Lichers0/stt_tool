import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @State private var activeTab: PopoverTab = .main
    @State private var historyVM: HistoryViewModel
    @State private var settingsVM: SettingsViewModel

    enum PopoverTab: String, CaseIterable {
        case main, history, settings

        var label: String {
            switch self {
            case .main: "Main"
            case .history: "History"
            case .settings: "Settings"
            }
        }
    }

    init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel
        self._historyVM = State(initialValue: HistoryViewModel(
            historyService: viewModel.services.historyService
        ))
        let settings = SettingsViewModel(
            services: viewModel.services,
            onModelChange: { model in
                viewModel.reloadModel(name: model)
            }
        )
        if let appDelegate = NSApp.delegate as? AppDelegate {
            settings.updater = appDelegate.updaterController.updater
        }
        self._settingsVM = State(initialValue: settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar at top
            tabBar
                .padding(.horizontal, DS.Spacing.md)
                .padding(.top, DS.Spacing.md)

            // Tab content — all tabs rendered, only active one visible.
            // This prevents MenuBarExtra window from collapsing on tab switch.
            MainView(viewModel: viewModel)
                .opacity(activeTab == .main ? 1 : 0)
                .frame(height: activeTab == .main ? nil : 0)
                .clipped()

            HistoryView(viewModel: historyVM)
                .opacity(activeTab == .history ? 1 : 0)
                .frame(height: activeTab == .history ? nil : 0)
                .clipped()

            SettingsView(viewModel: settingsVM)
                .opacity(activeTab == .settings ? 1 : 0)
                .frame(height: activeTab == .settings ? nil : 0)
                .clipped()
        }
        .frame(width: DS.Layout.popoverWidth)
        .transaction { $0.animation = nil }
        .onChange(of: activeTab) { _, newTab in
            if newTab == .history {
                historyVM.refresh()
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(PopoverTab.allCases, id: \.self) { tab in
                Button {
                    activeTab = tab
                } label: {
                    Text(tab.label)
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .fill(activeTab == tab
                                      ? Color(nsColor: .controlBackgroundColor)
                                      : Color.clear)
                                .shadow(color: activeTab == tab
                                        ? .black.opacity(0.06) : .clear,
                                        radius: 1, y: 1)
                        )
                        .foregroundStyle(activeTab == tab ? .primary : .secondary)
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
