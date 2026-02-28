import SwiftUI

// MARK: - Design Tokens

enum DS {

    // MARK: - Colors

    enum Colors {
        // Primary blue
        static let primary = Color.accentColor
        static let primarySubtle = Color.accentColor.opacity(0.1)

        // Destructive red
        static let destructive = Color.red
        static let destructiveSubtle = Color.red.opacity(0.1)

        // Status colors
        static let statusIdle = Color.secondary
        static let statusRecording = Color.red
        static let statusTranscribing = Color.orange
        static let statusInserting = Color.accentColor

        // Surfaces
        static let surfaceSubtle = Color(nsColor: .controlBackgroundColor).opacity(0.5)
        static let surfaceHover = Color(nsColor: .controlBackgroundColor).opacity(0.3)

        // Engine badge colors
        static let deepgramBadgeBg = Color.blue.opacity(0.1)
        static let deepgramBadgeFg = Color.blue
        static let whisperkitBadgeBg = Color.green.opacity(0.1)
        static let whisperkitBadgeFg = Color.green

        // Permission states
        static let grantedBg = Color.green.opacity(0.05)
        static let deniedBg = Color.red.opacity(0.05)

        // Overlay text states (pastel tones)
        static let overlayInterim = Color.white
        static let overlayInterimBlocked = Color(red: 1.0, green: 0.7, blue: 0.7)
        static let overlayFinalized = Color(red: 0.7, green: 1.0, blue: 0.7)
        static let overlayPasted = Color(red: 0.7, green: 0.85, blue: 1.0)
    }

    // MARK: - Typography

    enum Typography {
        static let header = Font.system(size: 14, weight: .semibold)
        static let body = Font.system(size: 13)
        static let caption = Font.system(size: 11)
        static let badgeFont = Font.system(size: 11, weight: .medium)
        static let tinyLabel = Font.system(size: 10, weight: .medium)
        static let monoCaption = Font.system(size: 11, weight: .regular, design: .monospaced)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    // MARK: - Radius

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
    }

    // MARK: - Layout

    enum Layout {
        static let popoverWidth: CGFloat = 400
        static let iconBoxSize: CGFloat = 32
        static let recordButtonHeight: CGFloat = 44
        static let statusDotSize: CGFloat = 6
        static let smallIconSize: CGFloat = 14
    }

    // MARK: - Animations

    static let pulseRecording = Animation.easeInOut(duration: 0.75).repeatForever(autoreverses: true)
    static let blink = Animation.easeInOut(duration: 0.4).repeatForever(autoreverses: true)
}

// MARK: - AppState Color Extension

extension AppState {
    var statusColor: Color {
        switch self {
        case .idle:
            DS.Colors.statusIdle
        case .recording, .streamingRecording:
            DS.Colors.statusRecording
        case .transcribing:
            DS.Colors.statusTranscribing
        case .inserting:
            DS.Colors.statusInserting
        case .error:
            DS.Colors.destructive
        }
    }
}
