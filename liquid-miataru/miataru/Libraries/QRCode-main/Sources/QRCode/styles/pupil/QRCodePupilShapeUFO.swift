//
//  Copyright © 2025 Darren Ford. All rights reserved.
//
//  MIT license
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
//  documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies or substantial
//  portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
//  WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
//  OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
//  OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import CoreGraphics
import Foundation

// MARK: - Pupil shape

public extension QRCode.PupilShape {
	/// A UFO style pupil shape
	@objc(QRCodePupilShapeUFO) class UFO: NSObject, QRCodePupilShapeGenerator {
		@objc public static var Name: String { "ufo" }
		/// The generator title
		@objc public static var Title: String { "UFO" }
		@objc public static func Create(_ settings: [String : Any]?) -> any QRCodePupilShapeGenerator {
			UFO(settings: settings)
		}

		/// Flip the pupil shape
		@objc public var flip: QRCode.Flip = .none

		@objc public init(flip: QRCode.Flip = .none) {
			self.flip = flip
			super.init()
		}

		/// Create a navigator pupil shape using the specified settings
		@objc public init(settings: [String: Any]?) {
			super.init()
			settings?.forEach { (key: String, value: Any) in
				_ = self.setSettingValue(value, forKey: key)
			}
		}

		/// Make a copy of the object
		@objc public func copyShape() -> any QRCodePupilShapeGenerator {
			UFO(flip: self.flip)
		}
		/// Reset the pupil shape generator back to defaults
		@objc public func reset() {
			self.flip = .none
		}

		/// The pupil centered in the 90x90 square
		@objc public func pupilPath() -> CGPath {
			switch self.flip {
			case .none:
				return pupilShape__
			case .horizontally:
				return CGPath.make(forceClosePath: true) { n in
					n.addPath(pupilShape__, transform: .init(scaleX: -1, y: 1).translatedBy(x: -90, y: 0))
				}
			case .vertically:
				return CGPath.make(forceClosePath: true) { n in
					n.addPath(pupilShape__, transform: .init(scaleX: 1, y: -1).translatedBy(x: 0, y: -90))
				}
			case .both:
				return CGPath.make(forceClosePath: true) { n in
					n.addPath(pupilShape__, transform: .init(scaleX: -1, y: -1).translatedBy(x: -90, y: -90))
				}
			}
		}
	}
}

private let pupilShape__: CGPath =
	CGPath.make { pupilPath in
		pupilPath.move(to: CGPoint(x: 60, y: 60))
		pupilPath.curve(to: CGPoint(x: 60, y: 45), controlPoint1: CGPoint(x: 60, y: 60), controlPoint2: CGPoint(x: 60, y: 45))
		pupilPath.curve(to: CGPoint(x: 45, y: 30), controlPoint1: CGPoint(x: 60, y: 36.72), controlPoint2: CGPoint(x: 53.28, y: 30))
		pupilPath.line(to: CGPoint(x: 30, y: 30))
		pupilPath.line(to: CGPoint(x: 30, y: 45))
		pupilPath.curve(to: CGPoint(x: 45, y: 60), controlPoint1: CGPoint(x: 30, y: 53.28), controlPoint2: CGPoint(x: 36.72, y: 60))
		pupilPath.line(to: CGPoint(x: 60, y: 60))
		pupilPath.line(to: CGPoint(x: 60, y: 60))
		pupilPath.close()
	}

public extension QRCode.PupilShape.UFO {
	@objc func settings() -> [String: Any] {
		[QRCode.SettingsKey.flip: self.flip.rawValue]
	}

	/// Returns true if the generator supports settings values for the given key
	@objc func supportsSettingValue(forKey key: String) -> Bool {
		key == QRCode.SettingsKey.flip
	}

	/// Set the key's value in the generator
	/// - Parameters:
	///   - value: The value to set
	///   - key: The setting key
	/// - Returns: True if the setting was able to be change, false otherwise
	@objc func setSettingValue(_ value: Any?, forKey key: String) -> Bool {
		if key == QRCode.SettingsKey.flip,
			let which = IntValue(value)
		{
			self.flip = QRCode.Flip(rawValue: which) ?? .none
			return true
		}
		return false
	}
}

public extension QRCodePupilShapeGenerator where Self == QRCode.PupilShape.UFO {
	/// Create a ufo pupil shape generator with curved insets
	/// - Parameter isFlipped: if true, flips the pupil shape horizontally
	/// - Returns: A pupil shape generator
	@inlinable static func ufo(flip: QRCode.Flip = .none) -> QRCodePupilShapeGenerator {
		QRCode.PupilShape.UFO(flip: flip)
	}
}
