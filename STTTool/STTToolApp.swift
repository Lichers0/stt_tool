import SwiftUI

@main
struct STTToolApp: App {
    @State private var services = ServiceContainer()
    @State private var viewModel: MenuBarViewModel?
    @State private var permissionsReady = false
    private let permissionsWindow = PermissionsWindowController()

    var body: some Scene {
        MenuBarExtra {
            if let viewModel {
                if permissionsReady {
                    MenuBarPopoverView(viewModel: viewModel)
                } else {
                    // Minimal view — clicking menu bar icon focuses the permissions window
                    VStack(spacing: DS.Spacing.md) {
                        Text("Setup required")
                            .font(DS.Typography.body)
                            .foregroundStyle(.secondary)
                        Button("Open Setup Window") {
                            permissionsWindow.focus()
                        }
                        .controlSize(.small)
                    }
                    .padding(DS.Spacing.xl)
                    .frame(width: 200)
                }
            } else {
                ProgressView("Loading...")
                    .padding()
                    .onAppear { initializeApp() }
            }
        } label: {
            Image(systemName: viewModel?.appState.systemImage ?? "mic")
        }
        .menuBarExtraStyle(.window)
    }

    private func initializeApp() {
        let vm = MenuBarViewModel(services: services)
        viewModel = vm

        services.permissionsService.checkPermissions()
        if services.permissionsService.allRequiredPermissionsGranted {
            permissionsReady = true
            vm.activate()
            loadModelIfNeeded(vm: vm)
        } else {
            permissionsWindow.show(
                permissionsService: services.permissionsService,
                keychainService: services.keychainService,
                onComplete: { [vm] in
                    permissionsReady = true
                    vm.activate()
                    loadModelIfNeeded(vm: vm)
                }
            )
        }
    }

    private func loadModelIfNeeded(vm: MenuBarViewModel) {
        let engine = UserDefaults.standard.string(
            forKey: Constants.deepgramEngineKey
        ) ?? Constants.defaultEngine
        if engine == "whisperkit" {
            vm.loadModelAtLaunch()
        }
    }
}
