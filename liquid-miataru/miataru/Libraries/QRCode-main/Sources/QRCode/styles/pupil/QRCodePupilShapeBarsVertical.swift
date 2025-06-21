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
	/// A vertical bars style pupil design
	@objc(QRCodePupilShapeBarsVertical) class BarsVertical: NSObject, QRCodePupilShapeGenerator {
		@objc public static var Name: String { "barsVertical" }
		/// The generator title
		@objc public static var Title: String { "Vertical bars" }
		@objc public static func Create(_ settings: [String : Any]?) -> any QRCodePupilShapeGenerator {
			BarsVertical()
		}

		/// Make a copy of the object
		@objc public func copyShape() -> any QRCodePupilShapeGenerator { BarsVertical() }
		/// Reset the pupil shape generator back to defaults
		@objc public func reset() { }

		@objc public func settings() -> [String : Any] { [:] }
		@objc public func supportsSettingValue(forKey key: String) -> Bool { false }
		@objc public func setSettingValue(_ value: Any?, forKey key: String) -> Bool { false }

		/// The pupil centered in the 90x90 square
		@objc public func pupilPath() -> CGPath {
			let roundedRectPupilPath = CGPath(roundedRect: CGRect(x: 30, y: 30, width: 9.33, height: 30), cornerWidth: 4, cornerHeight: 4, transform: nil)
			let roundedRectPupil2Path = CGPath(roundedRect: CGRect(x: 40.33, y: 30, width: 9.33, height: 30), cornerWidth: 4, cornerHeight: 4, transform: nil)
			let roundedRectPupil3Path = CGPath(roundedRect: CGRect(x: 50.66, y: 30, width: 9.33, height: 30), cornerWidth: 4, cornerHeight: 4, transform: nil)

			let result = CGMutablePath()
			result.addPath(roundedRectPupilPath)
			result.addPath(roundedRectPupil2Path)
			result.addPath(roundedRectPupil3Path)
			result.close()
			return result
		}
	}
}

public extension QRCode.PupilShape {
	/// A vertical bars style pupil design
	@objc(QRCodePupilShapeSquareBarsVertical) class SquareBarsVertical: NSObject, QRCodePupilShapeGenerator {
		@objc public static var Name: String { "barsVerticalSquare" }
		/// The generator title
		@objc public static var Title: String { "Square vertical bars" }
		@objc public static func Create(_ settings: [String : Any]?) -> any QRCodePupilShapeGenerator {
			SquareBarsVertical()
		}

		/// Make a copy of the object
		@objc public func copyShape() -> any QRCodePupilShapeGenerator { SquareBarsVertical() }
		/// Reset the pupil shape generator back to defaults
		@objc public func reset() { }

		@objc public func settings() -> [String : Any] { [:] }
		@objc public func supportsSettingValue(forKey key: String) -> Bool { false }
		@objc public func setSettingValue(_ value: Any?, forKey key: String) -> Bool { false }

		/// The pupil centered in the 90x90 square
		@objc public func pupilPath() -> CGPath {
			let roundedRectPupilPath = CGPath(rect: CGRect(x: 30, y: 30, width: 9.33, height: 30), transform: nil)
			let roundedRectPupil2Path = CGPath(rect: CGRect(x: 40.33, y: 30, width: 9.33, height: 30), transform: nil)
			let roundedRectPupil3Path = CGPath(rect: CGRect(x: 50.66, y: 30, width: 9.33, height: 30), transform: nil)

			let result = CGMutablePath()
			result.addPath(roundedRectPupilPath)
			result.addPath(roundedRectPupil2Path)
			result.addPath(roundedRectPupil3Path)
			result.close()
			return result
		}
	}
}

public extension QRCodePupilShapeGenerator where Self == QRCode.PupilShape.BarsVertical {
	/// Create a vertical bar pupil shape generator
	/// - Returns: A pupil shape generator
	@inlinable static func barsVerticalRounded() -> QRCodePupilShapeGenerator {
		QRCode.PupilShape.BarsVertical()
	}
}

public extension QRCodePupilShapeGenerator where Self == QRCode.PupilShape.SquareBarsVertical {
	/// Create a vertical bar pupil shape generator
	/// - Returns: A pupil shape generator
	@inlinable static func barsVerticalSquare() -> QRCodePupilShapeGenerator {
		QRCode.PupilShape.SquareBarsVertical()
	}
}
