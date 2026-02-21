import SwiftUI

@main
struct STTToolApp: App {
    @State private var services = ServiceContainer()
    @State private var viewModel: MenuBarViewModel?
    @State private var hasCompletedOnboarding = UserDefaults.standard.bool(
        forKey: Constants.hasCompletedOnboardingKey
    )

    var body: some Scene {
        MenuBarExtra {
            if let viewModel {
                if !hasCompletedOnboarding {
                    PermissionsPromptView(
                        permissionsService: services.permissionsService,
                        onComplete: {
                            UserDefaults.standard.set(true, forKey: Constants.hasCompletedOnboardingKey)
                            hasCompletedOnboarding = true
                        }
                    )
                } else {
                    MenuBarPopoverView(viewModel: viewModel)
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

        // Only preload WhisperKit model if it's the selected engine
        let engine = UserDefaults.standard.string(forKey: Constants.deepgramEngineKey) ?? Constants.defaultEngine
        if engine == "whisperkit" {
            vm.loadModelAtLaunch()
        }

        viewModel = vm
    }
}
