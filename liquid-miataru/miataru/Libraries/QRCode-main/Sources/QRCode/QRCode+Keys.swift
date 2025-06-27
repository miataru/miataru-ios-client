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

import Foundation

public extension QRCode {
	/// Constant Keys
	@objc class SettingsKey: NSObject {
		/// Settings key for 'corner radius fraction'
		@objc public static let cornerRadiusFraction = "cornerRadiusFraction"
		/// Settings key for 'insetFraction'
		@objc public static let insetFraction = "insetFraction"
		/// Settings key for 'has inner corners'
		@objc public static let hasInnerCorners = "hasInnerCorners"

		/// The generator to use when applying inset to modules
		@objc public static let insetGeneratorName = "insetGeneratorName"

		/// The generator to use when applying rotation to modules
		@objc public static let rotationGeneratorName = "rotationGeneratorName"

		/// A rotation angle (0 -> 1)
		@objc public static let rotationFraction = "rotationFraction"
		/// Setings key for 'random rotation'
		@objc public static let useRandomRotation = "useRandomRotation"
		/// Settings key for 'corners'
		@objc public static let corners = "corners"
		/// Settings key for 'additionalQuietSpace'
		@objc public static let additionalQuietZonePixels = "additionalQuietZonePixels"

//		/// Settings key for 'isFlipped'
//		@objc public static let isFlipped = "isFlipped"

		/// Settings for eye inner style
		@objc public static let eyeInnerStyle = "eyeInnerStyle"

		/// Settings key for 'Flip' (QRCode.Flip)
		@objc public static let flip = "flip"
	}
}

	// Backwards compatibility

extension QRCode.SettingsKey {
	/// Setings key for 'random inset'
	@objc public static let useRandomInset = "useRandomInset"
}
