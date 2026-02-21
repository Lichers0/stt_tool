import Foundation

enum AppState: Equatable {
    case idle
    case recording
    case streamingRecording
    case transcribing
    case inserting
    case error(String)

    var statusText: String {
        switch self {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording..."
        case .streamingRecording:
            return "Recording (streaming)..."
        case .transcribing:
            return "Transcribing..."
        case .inserting:
            return "Inserting text..."
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "mic"
        case .recording:
            return "mic.fill"
        case .streamingRecording:
            return "mic.fill"
        case .transcribing:
            return "text.bubble"
        case .inserting:
            return "doc.on.clipboard"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    var isRecording: Bool {
        self == .recording || self == .streamingRecording
    }

    var isBusy: Bool {
        switch self {
        case .recording, .streamingRecording, .transcribing, .inserting:
            return true
        default:
            return false
        }
    }
}
