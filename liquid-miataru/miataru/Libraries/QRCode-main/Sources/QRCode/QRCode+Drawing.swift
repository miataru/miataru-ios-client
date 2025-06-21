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

// MARK: - Drawing

public extension QRCode {
	/// Draw the current qrcode into the context using the specified style
	@objc func draw(
		ctx: CGContext,
		rect: CGRect,
		design: QRCode.Design,
		logoTemplate: QRCode.LogoTemplate? = nil
	) {
		// Only works with a 1:1 rect
		let sz = min(rect.width, rect.height)
		
		/// The size of each pixel in the output
		let additionalQuietSpacePixels = CGFloat(design.additionalQuietZonePixels)
		let dm: CGFloat = CGFloat(sz) / (CGFloat(self.cellDimension) + (2.0 * additionalQuietSpacePixels))
		let additionalQuietSpace = dm * additionalQuietSpacePixels
		
		// Factor in the additional quiet space in the result
		guard (2 * additionalQuietSpace) < sz else {
			Swift.print("additionalQuietSpace too large")
			return
		}
		
		let xoff = additionalQuietSpace + (rect.width - (CGFloat(self.cellDimension) * dm)) / 2.0
		let yoff = additionalQuietSpace + (rect.height - (CGFloat(self.cellDimension) * dm)) / 2.0
		
		// This is the final position for the generated qr code, inset within the final image
		let finalRect = rect.insetBy(dx: additionalQuietSpace, dy: additionalQuietSpace)

		// The size of a 'pixel' in the final image
		let pixelSize = finalRect.width / CGFloat(self.cellDimension)

		let style = design.style
		let shadow = style.shadow

		let mirrorEyePathsAroundQRCodeCenter = design.shape.mirrorEyePathsAroundQRCodeCenter

		//
		// Special case handling for the 'use pixel shape' eye and pupil types
		//
		if let eyePixelShape = design.shape.eye as? QRCode.EyeShape.UsePixelShape {
			eyePixelShape.pixelShape = design.shape.onPixels
		}
		if let pupilPixelShape = design.shape.pupil as? QRCode.PupilShape.UsePixelShape {
			pupilPixelShape.pixelShape = design.shape.onPixels
		}
		
		// Fill the background first
		let backgroundStyle = style.background ?? QRCode.FillStyle.clear
		ctx.usingGState { context in
			let cornerRadius = design.style.backgroundFractionalCornerRadius
			if cornerRadius > 0 {
				let computedRadius = CGFloat(cornerRadius) * dm
				context.addPath(
					CGPath(roundedRect: rect, cornerWidth: computedRadius, cornerHeight: computedRadius, transform: nil)
				)
				context.clip()
			}
			backgroundStyle.fill(ctx: context, rect: rect)
		}
		
		if design.shape.negatedOnPixelsOnly {
			var negatedMatrix = self.boolMatrix.inverted()
			if let logoTemplate = logoTemplate {
				negatedMatrix = logoTemplate.applyingMask(matrix: negatedMatrix, dimension: sz)
			}
			
			if let c = design.style.onPixelsBackground {
				let negatedPath = self.path(
					finalRect.size,
					components: .negative,
					shape: QRCode.Shape(onPixels: QRCode.PixelShape.Square()),
					logoTemplate: logoTemplate,
					additionalQuietSpace: additionalQuietSpace
				)
				ctx.usingGState { context in
					QRCode.FillStyle.Solid(c).fill(
						ctx: context,
						rect: finalRect,
						path: negatedPath,
						expectedPixelSize: pixelSize
					)
				}
			}

			// If the design specifies off pixels, add them
			if let s = style.offPixels, let shape = design.shape.offPixels {
				let offPath = self.path(
					finalRect.size,
					shape: QRCode.Shape(offPixels: shape),
					logoTemplate: logoTemplate,
					additionalQuietSpace: additionalQuietSpace,
					extendOffPixelsIntoEmptyQRCodeComponents: design.shape.extendOffPixelsIntoEmptyQRCodeComponents
				)
				ctx.usingGState { context in
					s.fill(
						ctx: context,
						rect: finalRect,
						path: offPath,
						expectedPixelSize: pixelSize,
						shadow: shadow
					)
				}

			}

			let negatedPath = self.path(
				finalRect.size,
				components: .negative,
				shape: design.shape,
				logoTemplate: logoTemplate,
				additionalQuietSpace: additionalQuietSpace
			)
			
			ctx.usingGState { context in
				style.onPixels.fill(
					ctx: context,
					rect: finalRect,
					path: negatedPath,
					expectedPixelSize: pixelSize,
					shadow: shadow
				)
			}
		}
		else {
			// Draw the background color behind the eyes
			if let eColor = design.style.eyeBackground {
				let eyeBackgroundPath = self.path(
					finalRect.size,
					components: .eyeBackground,
					shape: design.shape,
					logoTemplate: logoTemplate,
					additionalQuietSpace: additionalQuietSpace,
					mirrorEyePathsAroundQRCodeCenter: mirrorEyePathsAroundQRCodeCenter
				)
				ctx.usingGState { context in
					ctx.setFillColor(eColor)
					ctx.addPath(eyeBackgroundPath)
					ctx.fillPath()
				}
			}
			
			// Draw the outer eye
			let eyeOuterPath = self.path(
				finalRect.size,
				components: .eyeOuter,
				shape: design.shape,
				logoTemplate: logoTemplate,
				additionalQuietSpace: additionalQuietSpace,
				mirrorEyePathsAroundQRCodeCenter: mirrorEyePathsAroundQRCodeCenter
			)
			ctx.usingGState { context in
				style.actualEyeStyle.fill(
					ctx: context,
					rect: finalRect,
					path: eyeOuterPath,
					expectedPixelSize: pixelSize,
					shadow: shadow
				)
			}
			
			// Draw the eye 'pupil'
			let eyePupilPath = self.path(
				finalRect.size,
				components: .eyePupil,
				shape: design.shape,
				logoTemplate: logoTemplate,
				additionalQuietSpace: additionalQuietSpace,
				mirrorEyePathsAroundQRCodeCenter: mirrorEyePathsAroundQRCodeCenter
			)
			ctx.usingGState { context in
				style.actualPupilStyle.fill(
					ctx: context,
					rect: finalRect,
					path: eyePupilPath,
					expectedPixelSize: pixelSize,
					shadow: shadow
				)
			}

			// The 'off' pixels ONLY IF the user specifies both a offPixels shape AND an offPixels style.
			// Draw this first so it's guaranteed to be drawn behind the on-pixels
			if let s = style.offPixels, let _ = design.shape.offPixels {
				// Draw the 'off' pixels background IF the caller has set a color
				if let c = design.style.offPixelsBackground {
					let design: QRCode.Design = {
						let d = QRCode.Design()
						d.shape.offPixels = QRCode.PixelShape.Square()
						d.style.offPixels = QRCode.FillStyle.Solid(c)
						d.shape.extendOffPixelsIntoEmptyQRCodeComponents = design.shape.extendOffPixelsIntoEmptyQRCodeComponents
						return d
					}()
					let qrPath2 = self.path(
						finalRect.size,
						components: .offPixelsBackground,
						shape: design.shape,
						logoTemplate: logoTemplate,
						additionalQuietSpace: additionalQuietSpace,
						extendOffPixelsIntoEmptyQRCodeComponents: design.shape.extendOffPixelsIntoEmptyQRCodeComponents
					)
					ctx.usingGState { context in
						design.style.offPixels?.fill(
							ctx: context,
							rect: finalRect,
							path: qrPath2,
							expectedPixelSize: pixelSize,
							shadow: nil
						)
					}
				}

				let qrPath = self.path(
					finalRect.size,
					components: .offPixels,
					shape: design.shape,
					logoTemplate: logoTemplate,
					additionalQuietSpace: additionalQuietSpace,
					extendOffPixelsIntoEmptyQRCodeComponents: design.shape.extendOffPixelsIntoEmptyQRCodeComponents
				)
				ctx.usingGState { context in
					s.fill(
						ctx: context,
						rect: finalRect,
						path: qrPath,
						expectedPixelSize: pixelSize,
						shadow: nil
					)
				}
			}

			// Now, the 'on' pixels background
			if let c = design.style.onPixelsBackground {
				let design: QRCode.Design = {
					let d = QRCode.Design()
					d.shape.onPixels = QRCode.PixelShape.Square()
					d.style.onPixels = QRCode.FillStyle.Solid(c)
					return d
				}()
				
				let qrPath2 = self.path(
					finalRect.size,
					components: .onPixels,
					shape: design.shape,
					logoTemplate: logoTemplate,
					additionalQuietSpace: additionalQuietSpace
				)
				ctx.usingGState { context in
					design.style.onPixels.fill(
						ctx: context,
						rect: finalRect,
						path: qrPath2,
						expectedPixelSize: pixelSize,
						shadow: shadow
					)
				}
			}
			
			// Now, the 'on' pixels
			let qrPath = self.path(
				finalRect.size,
				components: .onPixels,
				shape: design.shape,
				logoTemplate: logoTemplate,
				additionalQuietSpace: additionalQuietSpace
			)
			ctx.usingGState { context in
				style.onPixels.fill(
					ctx: context,
					rect: finalRect,
					path: qrPath,
					expectedPixelSize: pixelSize,
					shadow: shadow
				)
			}
		}
		
		if let logoTemplate = logoTemplate {
			ctx.usingGState { context in
				// Get the absolute rect within the generated image of the mask path
				let absMask = logoTemplate.absolutePathForMaskPath(
					dimension: min(finalRect.width, finalRect.height),
					flipped: true
				)
				
				// logo drawing is flipped.
				context.scaleBy(x: 1, y: -1)
				context.translateBy(x: xoff - additionalQuietSpace, y: yoff - rect.height - additionalQuietSpace)
				
				// Clip to the mask path.
				context.addPath(absMask)
				context.clip()
				
				// Draw the logo image into the mask bounds
				context.draw(logoTemplate.image, in: absMask.boundingBoxOfPath.insetBy(dx: logoTemplate.inset, dy: logoTemplate.inset))
			}
		}
	}
}
