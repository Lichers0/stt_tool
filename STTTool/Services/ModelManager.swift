import Foundation
import WhisperKit

@MainActor
final class ModelManager: ObservableObject, ModelManagerProtocol {
    let availableModels = Constants.availableModels

    @Published var selectedModel: String {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: Constants.selectedModelKey)
        }
    }

    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0

    init() {
        self.selectedModel = UserDefaults.standard.string(
            forKey: Constants.selectedModelKey
        ) ?? Constants.defaultModel
    }

    func recommendedModel() -> String {
        // On Apple Silicon with 16GB+, recommend small; otherwise base
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryGB = Double(totalMemory) / (1024 * 1024 * 1024)

        if memoryGB >= 32 {
            return "large-v3_turbo"
        } else if memoryGB >= 16 {
            return "small"
        } else {
            return "base"
        }
    }
}
