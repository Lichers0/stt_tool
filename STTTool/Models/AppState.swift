import Foundation

enum AppState: Equatable {
    case idle
    case recording
    case transcribing
    case inserting
    case error(String)

    var statusText: String {
        switch self {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording..."
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
        case .transcribing:
            return "text.bubble"
        case .inserting:
            return "doc.on.clipboard"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    var isRecording: Bool {
        self == .recording
    }

    var isBusy: Bool {
        switch self {
        case .recording, .transcribing, .inserting:
            return true
        default:
            return false
        }
    }
}
