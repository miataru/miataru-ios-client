import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum Haptic {
	public static func notifySuccess() {
		performNotification(.success)
	}

	public static func notifyWarning() {
		performNotification(.warning)
	}

	public static func notifyError() {
		performNotification(.error)
	}

	private enum NotificationType {
		case success
		case warning
		case error
	}

	private static func performNotification(_ type: NotificationType) {
		#if canImport(UIKit)
		DispatchQueue.main.async {
			let generator = UINotificationFeedbackGenerator()
			generator.prepare()
			switch type {
			case .success:
				generator.notificationOccurred(.success)
			case .warning:
				generator.notificationOccurred(.warning)
			case .error:
				generator.notificationOccurred(.error)
			}
		}
		#elseif canImport(AppKit)
		// macOS provides limited, generic haptic feedback
		DispatchQueue.main.async {
			NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
		}
		#else
		// No-op on unsupported platforms
		#endif
	}
}


