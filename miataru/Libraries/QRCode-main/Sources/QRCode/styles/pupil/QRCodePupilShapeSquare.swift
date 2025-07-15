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
	@objc(QRCodePupilShapeSquare) class Square: NSObject, QRCodePupilShapeGenerator {
		@objc public static var Name: String { "square" }
		/// The generator title
		@objc public static var Title: String { "Square" }
		
		@objc public static func Create(_ settings: [String : Any]?) -> any QRCodePupilShapeGenerator {
			Square()
		}

		/// Make a copy of the object
		@objc public func copyShape() -> any QRCodePupilShapeGenerator { Square() }
		/// Reset the pupil shape generator back to defaults
		@objc public func reset() { }

		@objc public func settings() -> [String : Any] { [:] }
		@objc public func supportsSettingValue(forKey key: String) -> Bool { false }
		@objc public func setSettingValue(_ value: Any?, forKey key: String) -> Bool { false }

		/// The pupil centered in the 90x90 square
		@objc public func pupilPath() -> CGPath {
			return CGPath(rect: CGRect(x: 30, y: 30, width: 30, height: 30), transform: nil)
		}
	}
}

public extension QRCodePupilShapeGenerator where Self == QRCode.PupilShape.Square {
	/// Create a square pupil shape generator
	/// - Returns: A pupil shape generator
	@inlinable static func square() -> QRCodePupilShapeGenerator { QRCode.PupilShape.Square() }
}
