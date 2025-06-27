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

public extension QRCode.EyeShape {
	/// A 'pixel' style eye design which provides corner radius configuration
	@objc(QRCodeEyeShapePixels) class Pixels: NSObject, QRCodeEyeShapeGenerator {
		@objc public static let Name = "pixels"
		@objc public static var Title: String { "Pixels" }

		@objc public static let DefaultCornerRadius = 0.65

		@objc public static func Create(_ settings: [String: Any]?) -> any QRCodeEyeShapeGenerator {
			let radius = DoubleValue(settings?[QRCode.SettingsKey.cornerRadiusFraction]) ?? Self.DefaultCornerRadius
			return Pixels(cornerRadiusFraction: radius)
		}

		@objc public func settings() -> [String: Any] { [QRCode.SettingsKey.cornerRadiusFraction: self.cornerRadiusFraction] }
		@objc public func supportsSettingValue(forKey key: String) -> Bool { key == QRCode.SettingsKey.cornerRadiusFraction }
		@objc public func setSettingValue(_ value: Any?, forKey key: String) -> Bool {
			if key == QRCode.SettingsKey.cornerRadiusFraction, let value = DoubleValue(value) {
				cornerRadiusFraction = max(0, min(1, value))
				return true
			}
			return false
		}

		/// Make a copy of the object
		@objc public func copyShape() -> any QRCodeEyeShapeGenerator {
			return Self.Create(self.settings())
		}

		/// Reset the eye shape generator back to defaults
		@objc public func reset() {
			self.cornerRadiusFraction = Self.DefaultCornerRadius
		}

		private var _actualCornerRadius: CGFloat

		/// The corner radius
		@objc public var cornerRadiusFraction: CGFloat {
			didSet { 
				self._actualCornerRadius = self.cornerRadiusFraction.clamped(to: 0 ... 1) * 5.0
			}
		}

		/// Create a pixel eye shape
		/// - Parameter cornerRadiusFraction: The corner radius
		@objc public init(cornerRadiusFraction: CGFloat = QRCode.EyeShape.Pixels.DefaultCornerRadius) {
			self.cornerRadiusFraction = cornerRadiusFraction.clamped(to: 0 ... 1)
			self._actualCornerRadius = self.cornerRadiusFraction * 5.0
		}

		public func eyePath() -> CGPath {
			let path = CGMutablePath()

			path.addPath(CGPath(roundedRect: CGRect(x: 10, y: 10, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 10, y: 10, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))

			path.addPath(CGPath(roundedRect: CGRect(x: 10, y: 10, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 10, y: 20, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 10, y: 30, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 10, y: 40, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 10, y: 50, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 10, y: 60, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 10, y: 70, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))

			path.addPath(CGPath(roundedRect: CGRect(x: 70, y: 10, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 70, y: 20, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 70, y: 30, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 70, y: 40, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 70, y: 50, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 70, y: 60, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 70, y: 70, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))

			path.addPath(CGPath(roundedRect: CGRect(x: 20, y: 10, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 30, y: 10, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 40, y: 10, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 50, y: 10, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 60, y: 10, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))

			path.addPath(CGPath(roundedRect: CGRect(x: 20, y: 70, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 30, y: 70, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 40, y: 70, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 50, y: 70, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))
			path.addPath(CGPath(roundedRect: CGRect(x: 60, y: 70, width: 9, height: 9), cornerWidth: self._actualCornerRadius, cornerHeight: self._actualCornerRadius, transform: nil))

			return path
		}

		@objc public func eyeBackgroundPath() -> CGPath {
			CGPath(rect: CGRect(origin: .zero, size: CGSize(width: 90, height: 90)), transform: nil)
		}

		private static let _defaultPupil = QRCode.PupilShape.Pixels()
		public func defaultPupil() -> any QRCodePupilShapeGenerator {
			QRCode.PupilShape.Pixels(cornerRadiusFraction: self.cornerRadiusFraction)
		}
	}
}

public extension QRCodeEyeShapeGenerator where Self == QRCode.EyeShape.Pixels {
	/// Create a pixels eye shape generator
	/// - Parameter cornerRadiusFraction: The fractional corner radius to apply to each pixel
	/// - Returns: An eye shape generator
	@inlinable static func pixels(
		cornerRadiusFraction: CGFloat = QRCode.EyeShape.Pixels.DefaultCornerRadius
	) -> QRCodeEyeShapeGenerator {
		QRCode.EyeShape.Pixels(cornerRadiusFraction: cornerRadiusFraction)
	}
}
