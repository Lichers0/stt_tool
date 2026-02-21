import SwiftUI

@main
struct STTToolApp: App {
    @State private var services = ServiceContainer()
    @State private var viewModel: MenuBarViewModel?
    @State private var permissionsReady = false

    var body: some Scene {
        MenuBarExtra {
            if let viewModel {
                if permissionsReady {
                    MenuBarPopoverView(viewModel: viewModel)
                } else {
                    StartupGuardianView(
                        permissionsService: services.permissionsService,
                        keychainService: services.keychainService,
                        onComplete: {
                            permissionsReady = true
                            viewModel.activate()
                            loadModelIfNeeded(vm: viewModel)
                        }
                    )
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

        // If all permissions already granted, skip guardian
        services.permissionsService.checkPermissions()
        if services.permissionsService.allRequiredPermissionsGranted {
            permissionsReady = true
            vm.activate()
            loadModelIfNeeded(vm: vm)
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
