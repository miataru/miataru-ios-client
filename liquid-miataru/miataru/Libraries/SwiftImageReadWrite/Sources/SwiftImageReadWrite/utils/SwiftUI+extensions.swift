//
//  Copyright © 2024 Darren Ford. All rights reserved.
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

#if canImport(CoreGraphics)

import Foundation

#if canImport(SwiftUI)
import SwiftUI

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension PlatformImage {
	func imageUI(label: Text) -> SwiftUI.Image {
#if os(macOS)
		SwiftUI.Image(nsImage: self)
#else
		SwiftUI.Image(uiImage: self)
#endif
	}
}

extension CGImage {
	@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
	/// Return a SwiftUI Image representation of this CGImage
	/// - Parameters:
	///   - scale: The scale to apply to the resulting image
	///   - label: The label
	/// - Returns: A SwiftUI image
	func imageUI(scale: CGFloat = 1.0, label: Text) -> SwiftUI.Image {
		SwiftUI.Image(self, scale: scale, label: label)
	}
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public extension CGImage.ImageRepresentation {
	/// Return a SwiftUI Image representation of this CGImage
	/// - Parameter
	///   - scale: The image scale
	///   - label: The label
	/// - Returns: An image
	func swiftUI(scale: CGFloat = 1.0, label: Text) -> SwiftUI.Image {
		owner.imageUI(scale: scale, label: label)
	}
}

#endif

#endif
