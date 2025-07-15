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

public extension QRCode.PixelShape {
	@objc(QRCodePixelShapeHorizontal) class Horizontal: NSObject, QRCodePixelShapeGenerator {
		/// The generator name
		@objc static public let Name: String = "horizontal"
		/// The generator title
		@objc public static var Title: String { "Horizontal bars" }

		/// This pupil generator can be used when generating eye and pupil shapes
		@objc public var canGenerateEyeAndPupilShapes: Bool { true }

		/// Default inset value
		@objc public static let DefaultInset: CGFloat = 0.1
		/// Default corner radius value
		@objc public static let DefaultCornerRadius: CGFloat = 1

		/// Create an instance of this path generator with the specified settings
		@objc static public func Create(_ settings: [String: Any]?) -> any QRCodePixelShapeGenerator {
			let insetFraction = DoubleValue(settings?[QRCode.SettingsKey.insetFraction]) ?? Self.DefaultInset
			let radius = DoubleValue(settings?[QRCode.SettingsKey.cornerRadiusFraction]) ?? Self.DefaultCornerRadius
			return QRCode.PixelShape.Horizontal(insetFraction: insetFraction, cornerRadiusFraction: radius)
		}

		/// Make a copy of the object
		@objc public func copyShape() -> any QRCodePixelShapeGenerator {
			return Horizontal(
				insetFraction: self.insetFraction,
				cornerRadiusFraction: self.cornerRadiusFraction
			)
		}

		/// Reset the generator back to defaults
		@objc public func reset() {
			self.cornerRadiusFraction = Self.DefaultCornerRadius
			self.insetFraction = Self.DefaultInset
		}

		// The fractional inset for the pixel
		var insetFraction: CGFloat
		// The fractional corner radius
		var cornerRadiusFraction: CGFloat

		/// Create a generator with a specified inset fraction and corner radius fraction
		@objc public init(
			insetFraction: CGFloat = QRCode.PixelShape.Horizontal.DefaultInset,
			cornerRadiusFraction: CGFloat = QRCode.PixelShape.Horizontal.DefaultCornerRadius
		) {
			self.insetFraction = insetFraction.clamped(to: 0...1)
			self.cornerRadiusFraction = cornerRadiusFraction.clamped(to: 0...1)
			super.init()
		}

		/// Generate a CGPath from the matrix contents
		/// - Parameters:
		///   - matrix: The matrix to generate
		///   - size: The size of the resulting CGPath
		/// - Returns: A path
		@objc public func generatePath(from matrix: BoolMatrix, size: CGSize) -> CGPath {
			let dx = size.width / CGFloat(matrix.dimension)
			let dy = size.height / CGFloat(matrix.dimension)
			let dm = min(dx, dy)

			let xoff = (size.width - (CGFloat(matrix.dimension) * dm)) / 2.0
			let yoff = (size.height - (CGFloat(matrix.dimension) * dm)) / 2.0

			let path = CGMutablePath()

			for row in 0 ..< matrix.dimension {
				var activeRect: CGRect?

				for col in 0 ..< matrix.dimension {
					if matrix[row, col] == false {
						if let r = activeRect {
							// We had an active rect. Close it.
							let ri = r.insetBy(dx: self.insetFraction * r.height / 2.0, dy: self.insetFraction * r.height / 2.0)
							let cr = (ri.height / 2.0) * self.cornerRadiusFraction
							path.addPath(CGPath(roundedRect: ri, cornerWidth: cr, cornerHeight: cr, transform: nil))
						}
						activeRect = nil
					}
					else if activeRect != nil {
						// We are still going...
						activeRect?.size.width += dm
					}
					else {
						// Starting a new rect
						activeRect = CGRect(x: xoff + (CGFloat(col) * dm), y: yoff + (CGFloat(row) * dm), width: dm, height: dm)
					}
				}

				if let r = activeRect {
					// Close the rect
					let ri = r.insetBy(dx: self.insetFraction * r.height / 2.0, dy: self.insetFraction * r.height / 2.0)
					let cr = (ri.height / 2.0) * self.cornerRadiusFraction
					path.addPath(CGPath(roundedRect: ri, cornerWidth: cr, cornerHeight: cr, transform: nil))
				}
			}

			return path
		}
	}
}

// MARK: - Settings

public extension QRCode.PixelShape.Horizontal {
	/// Does the shape generator support setting values for a particular key?
	@objc func supportsSettingValue(forKey key: String) -> Bool {
		return key == QRCode.SettingsKey.insetFraction
			 || key == QRCode.SettingsKey.cornerRadiusFraction
	}

	/// Returns a storable representation of the shape handler
	@objc func settings() -> [String : Any] {
		return [
			QRCode.SettingsKey.insetFraction: self.insetFraction,
			QRCode.SettingsKey.cornerRadiusFraction: self.cornerRadiusFraction
		]
	}

	/// Set a configuration value for a particular setting string
	@objc func setSettingValue(_ value: Any?, forKey key: String) -> Bool {
		if key == QRCode.SettingsKey.insetFraction {
			guard let v = value else {
				self.insetFraction = Self.DefaultInset
				return true
			}
			guard let v = DoubleValue(v) else { return false }
			self.insetFraction = v
			return true
		}
		else if key == QRCode.SettingsKey.cornerRadiusFraction {
			guard let v = value else {
				self.cornerRadiusFraction = Self.DefaultCornerRadius
				return true
			}
			guard let v = DoubleValue(v) else { return false }
			self.cornerRadiusFraction = v
			return true
		}
		return false
	}
}

// MARK: - Pixel creation conveniences

public extension QRCodePixelShapeGenerator where Self == QRCode.PixelShape.Horizontal {
	/// Create a horizontal pixel generator
	/// - Parameters:
	///   - insetFraction: The inset fraction (0.0 -> 1.0)
	///   - cornerRadiusFraction: The corner radius fraction (0.0 -> 1.0)
	/// - Returns: A pixel generator
	@inlinable static func horizontal(
		insetFraction: CGFloat = QRCode.PixelShape.Vertical.DefaultInset,
		cornerRadiusFraction: CGFloat = QRCode.PixelShape.Vertical.DefaultCornerRadius
	) -> QRCodePixelShapeGenerator {
		QRCode.PixelShape.Horizontal(
			insetFraction: insetFraction,
			cornerRadiusFraction: cornerRadiusFraction
		)
	}
}
