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

#if os(macOS)
import AppKit.NSImage
#else
import UIKit.UIImage
#endif

extension PlatformImage {
	/// Load an image from a file URL
	/// - Parameter fileURL: The url for the file containing the image
	/// - Returns: An image, or nil if the file was not an image
	public static func load(fileURL: URL) throws -> PlatformImage {
		assert(fileURL.isFileURL)
		#if os(macOS)
		guard let image = PlatformImage(contentsOf: fileURL) else {
			throw ImageReadWriteError.unableToDecodeImage
		}
		return image
		#else
		guard let image = PlatformImage(contentsOfFile: fileURL.path) else {
			throw ImageReadWriteError.unableToDecodeImage
		}
		return image
		#endif
	}

	/// Load an image from raw data
	/// - Parameter data: The data containing the image
	/// - Returns: An image, or nil if the data did not contain an image
	public static func load(data: Data) throws -> PlatformImage {
		guard let image = PlatformImage(data: data) else {
			throw ImageReadWriteError.unableToDecodeImage
		}
		return image
	}
}

#endif
