/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * Haptics.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

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

	public static func impactMedium() {
		performImpact(.medium)
	}

	public static func impactLight() {
		performImpact(.light)
	}

	public static func impactHeavy() {
		performImpact(.heavy)
	}

	private enum NotificationType {
		case success
		case warning
		case error
	}

	private enum ImpactStyle {
		case light
		case medium
		case heavy
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

	private static func performImpact(_ style: ImpactStyle) {
		#if canImport(UIKit)
		DispatchQueue.main.async {
			let uiStyle: UIImpactFeedbackGenerator.FeedbackStyle
			switch style {
			case .light:
				uiStyle = .light
			case .medium:
				uiStyle = .medium
			case .heavy:
				uiStyle = .heavy
			}
			let generator = UIImpactFeedbackGenerator(style: uiStyle)
			generator.prepare()
			generator.impactOccurred()
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


