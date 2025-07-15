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
	/// A 'square' style pupil design
	@objc(QRCodePupilShapePixels) class Pixels: NSObject, QRCodePupilShapeGenerator {
		@objc public static var Name: String { "pixels" }
		/// The generator title
		@objc public static var Title: String { "Pixels" }

		@objc public static let DefaultCornerRadius = 0.65

		@objc public static func Create(_ settings: [String: Any]?) -> any QRCodePupilShapeGenerator {
			let radius = DoubleValue(settings?[QRCode.SettingsKey.cornerRadiusFraction]) ?? Self.DefaultCornerRadius
			return Pixels(cornerRadiusFraction: radius)
		}

		/// Make a copy of the object
		@objc public func copyShape() -> any QRCodePupilShapeGenerator {
			Pixels(cornerRadiusFraction: self.cornerRadiusFraction)
		}
		/// Reset the pupil shape generator back to defaults
		@objc public func reset() {
			self.cornerRadiusFraction = Self.DefaultCornerRadius
		}

		@objc public func settings() -> [String: Any] {
			[ QRCode.SettingsKey.cornerRadiusFraction: self.cornerRadiusFraction ]
		}
		@objc public func supportsSettingValue(forKey key: String) -> Bool { key == QRCode.SettingsKey.cornerRadiusFraction }
		@objc public func setSettingValue(_ value: Any?, forKey key: String) -> Bool {
			if key == QRCode.SettingsKey.cornerRadiusFraction, let value = DoubleValue(value) {
				cornerRadiusFraction = max(0, min(1, value))
				return true
			}
			return false
		}

		@objc public var cornerRadiusFraction: CGFloat {
			didSet {
				self._actualCornerRadius = self.cornerRadiusFraction.unitClamped() * 5.0
			}
		}

		@objc public init(cornerRadiusFraction: CGFloat = QRCode.PupilShape.Pixels.DefaultCornerRadius) {
			self.cornerRadiusFraction = cornerRadiusFraction
			self._actualCornerRadius = cornerRadiusFraction.unitClamped() * 5.0
		}

		/// The pupil centered in the 90x90 square
		@objc public func pupilPath() -> CGPath {
			let path = CGMutablePath()
			path.addPath(CGPath(roundedRect: CGRect(x: 30, y: 30, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 40, y: 30, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 50, y: 30, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 30, y: 40, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 40, y: 40, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 50, y: 40, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 30, y: 50, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 40, y: 50, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 50, y: 50, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			return path
		}

		private var _actualCornerRadius: CGFloat
	}
}

public extension QRCodePupilShapeGenerator where Self == QRCode.PupilShape.Pixels {
	/// Create a pixels pupil shape generator with curved insets
	/// - Parameter cornerRadiusFraction: the fractional (0...1) corner radius for the pixels
	/// - Returns: A pupil shape generator
	@inlinable static func pixels(
		cornerRadiusFraction: CGFloat = QRCode.PupilShape.Pixels.DefaultCornerRadius
	) -> QRCodePupilShapeGenerator {
		QRCode.PupilShape.Pixels(cornerRadiusFraction: cornerRadiusFraction)
	}
}
