import Foundation

// Passthrough pipeline -- ready for future LLM processing steps
final class TextProcessingPipeline: TextProcessingPipelineProtocol, @unchecked Sendable {
    func process(_ text: String) async -> String {
        return text
    }
}
