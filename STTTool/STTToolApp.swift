import SwiftUI
import Sparkle

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let services = ServiceContainer()
    @Published var viewModel: MenuBarViewModel?
    @Published var permissionsReady = false
    let permissionsWindow = PermissionsWindowController()
    let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        initializeApp()
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
                onComplete: { [weak self, vm] in
                    self?.permissionsReady = true
                    vm.activate()
                    self?.loadModelIfNeeded(vm: vm)
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

// MARK: - Menu Bar Content

private struct MenuBarContentView: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        if let viewModel = appDelegate.viewModel {
            if appDelegate.permissionsReady {
                MenuBarPopoverView(viewModel: viewModel)
            } else {
                // Minimal view — clicking menu bar icon focuses the permissions window
                VStack(spacing: DS.Spacing.md) {
                    Text("Setup required")
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                    Button("Open Setup Window") {
                        appDelegate.permissionsWindow.focus()
                    }
                    .controlSize(.small)
                }
                .padding(DS.Spacing.xl)
                .frame(width: 200)
            }
        } else {
            ProgressView("Loading...")
                .padding()
        }
    }
}

// MARK: - App

@main
struct STTToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appDelegate: appDelegate)
        } label: {
            Image(systemName: appDelegate.viewModel?.appState.systemImage ?? "mic")
        }
        .menuBarExtraStyle(.window)
    }
}
