import XCTest
@testable import QRCode

final class QRCodeMaskingTests: XCTestCase {

	let outputFolder = try! testResultsContainer.subfolder(with: "QRCodeMaskingTests")

	func testBasicMask() throws {
		let code = try QRCode.Document(
			utf8String: "https://www.apple.com/au/mac-studio/",
			errorCorrection: .high,
			engine: __testEngine
		)

		let image = try resourceImage(for: "colored-fill", extension: "jpg")

		do {
			let p = CGPath(ellipseIn: CGRect(x: 0.30, y: 0.30, width: 0.40, height: 0.40), transform: nil)
			let t = QRCode.LogoTemplate(image: image, path: p)
			code.logoTemplate = t

			let svg = try code.svg(dimension: 600)
			try outputFolder.write(svg, to: "testBasicMask1.svg")

			let image = try code.platformImage(dimension: 300, dpi: 144)
			let data = try image.representation.png()
			try outputFolder.write(data, to: "testBasicMask1.png")
		}

		do {
			let p = CGPath(rect: CGRect(x: 0.35, y: 0.35, width: 0.30, height: 0.30), transform: nil)
			let t = QRCode.LogoTemplate(image: image, path: p)
			code.logoTemplate = t

			let svg = try code.svg(dimension: 600)
			try outputFolder.write(svg, to: "testBasicMask2.svg")

			let image = try code.platformImage(dimension: 300, dpi: 144)
			let data = try image.representation.png()
			try outputFolder.write(data, to: "testBasicMask2.png")
		}
	}

	func testAbsolutePositioningMask() throws {
		let code = try QRCode.Document(
			utf8String: "https://www.apple.com/au/mac-studio/",
			errorCorrection: .high,
			engine: __testEngine
		)

		let image2 = try resourceImage(for: "colored-fill", extension: "jpg")

		let p = CGPath(rect: CGRect(x: 0.35, y: 0.35, width: 0.30, height: 0.30), transform: nil)
		let t = QRCode.LogoTemplate(image: image2, path: p)

		code.logoTemplate = t
		#if os(macOS)
		let image = try code.nsImage(dimension: 300)
		_ = image
		#endif

		/// absolute mask for a 100 px dimension should just be the same as the mask
		let absMask = t.absolutePathForMaskPath(dimension: 1)
		XCTAssertEqual(p, absMask)

		/// absolute mask for a 200 px dimension should be 200x the size of the mask
		let absMask2 = t.absolutePathForMaskPath(dimension: 200)
		let scaled: CGPath = {
			let x = CGMutablePath()
			x.addPath(p, transform: CGAffineTransform(scaleX: 200, y: 200))
			return x
		}()
		XCTAssertEqual(absMask2, scaled)

		// TODO: Need more tests here
	}

	func testOverlayImage() throws {

		let code = try QRCode.Document(
			utf8String: "https://www.apple.com/au/mac-studio/",
			errorCorrection: .high,
			engine: __testEngine
		)

		code.design.shape.onPixels = QRCode.PixelShape.CurvePixel(cornerRadiusFraction: 0.9)

		do {
			// Lower right logo
			let logoImage = try resourceImage(for: "instagram-icon", extension: "png")
			code.logoTemplate = QRCode.LogoTemplate(
				image: logoImage,
				path: CGPath(ellipseIn: CGRect(x: 0.65, y: 0.65, width: 0.30, height: 0.30), transform: nil),
				inset: 8
			)

			let logoQRCode = try code.platformImage(dimension: 300)
			let data = try logoQRCode.representation.png()
			try outputFolder.write(data, to: "logo-lower-right-logo-small.png")

			let logoQRCode2 = try code.platformImage(dimension: 512)
			let data2 = try logoQRCode2.representation.png()
			try outputFolder.write(data2, to: "logo-lower-right-logo-larger.png")

			let str = try code.svg(dimension: 512)
			try outputFolder.write(str, to: "logo-lower-right-logo-larger.svg")
		}

		do {
			// Centered square logo
			let logoImage = try resourceImage(for: "square-logo", extension: "png")

			let logo = QRCode.LogoTemplate(
				image: logoImage,
				path: CGPath(rect: CGRect(x: 0.35, y: 0.35, width: 0.30, height: 0.30), transform: nil),
				inset: 8
			)
			code.logoTemplate = logo

			let logoQRCode = try code.platformImage(dimension: 600)
			let data = try logoQRCode.representation.png()
			try outputFolder.write(data, to: "logo-center-square-logo.png")
		}

		do {
			// rectangular, non-centered
			let logoImage = try resourceImage(for: "apple", extension: "png")

			let logo = QRCode.LogoTemplate(
				image: logoImage,
				path: CGPath(rect: CGRect(x: 0.40, y: 0.365, width: 0.55, height: 0.25), transform: nil),
				inset: 8
			)
			code.logoTemplate = logo

			let logoQRCode = try code.platformImage(dimension: 512)
			let data = try logoQRCode.representation.png()
			try outputFolder.write(data, to: "logo-rectangular-non-centered.png")

			let logo2 = QRCode.LogoTemplate(
				image: logoImage,
				path: CGPath(rect: CGRect(x: 0.40, y: 0.365, width: 0.55, height: 0.25), transform: nil),
				inset: 32
			)
			code.logoTemplate = logo2

			let logoQRCode2 = try code.platformImage(dimension: 3000)
			let data2 = try logoQRCode2.representation.png()
			try outputFolder.write(data2, to: "logo-rectangular-non-centered-large.png")

			let str = try code.svg(dimension: 3000)
			try outputFolder.write(str, to: "logo-rectangular-non-centered-large.svg")
		}
	}

	func testFixedTemplates() throws {
		let code = try QRCode.Document(
			utf8String: "Verifying that pre-built logo templates work as expected",
			errorCorrection: .high,
			engine: __testEngine
		)

		do {
			let logoImage = try resourceImage(for: "instagram-icon", extension: "png")
			code.logoTemplate = .CircleCenter(image: logoImage)

			let logo1 = try code.platformImage(dimension: 300)
			let data2 = try logo1.representation.png()
			try outputFolder.write(data2, to: "fixed-template-circle-center.png")
		}

		do {
			let logoImage = try resourceImage(for: "instagram-icon", extension: "png")
			code.logoTemplate = QRCode.LogoTemplate.CircleBottomRight(image: logoImage)

			let logo1 = try code.platformImage(dimension: 300)
			let data2 = try logo1.representation.png()
			try outputFolder.write(data2, to: "fixed-template-circle-bottom-right.png")
		}

		do {
			let logoImage = try resourceImage(for: "square-logo", extension: "png")
			code.logoTemplate = QRCode.LogoTemplate.SquareCenter(image: logoImage)

			let logo1 = try code.platformImage(dimension: 300)
			let data2 = try logo1.representation.png()
			try outputFolder.write(data2, to: "fixed-template-square-center.png")
		}

		do {
			let logoImage = try resourceImage(for: "square-logo", extension: "png")
			code.logoTemplate = QRCode.LogoTemplate.SquareBottomRight(image: logoImage)

			let logo1 = try code.platformImage(dimension: 300)
			let data2 = try logo1.representation.png()
			try outputFolder.write(data2, to: "fixed-template-square-bottom-right.png")
		}
	}

	func testLogoImageMasking() throws {
		let doc = try QRCode.Document(
			utf8String: "Verifying logo image masking works",
			errorCorrection: .high,
			engine: __testEngine
		)

		let image = try resourceImage(for: "logo", extension: "png")

		do {
			doc.logoTemplate = QRCode.LogoTemplate(image: image)

			let logo1 = try doc.platformImage(dimension: 300)
			let data2 = try logo1.representation.png()
			try outputFolder.write(data2, to: "logotemplate-image-transparency-mask.png")
		}

		do {
			let imageMask = try resourceImage(for: "logo-mask", extension: "png")
			doc.logoTemplate = QRCode.LogoTemplate(image: image, maskImage: imageMask)

			let logo1 = try doc.platformImage(dimension: 300)
			let data2 = try logo1.representation.png()
			try outputFolder.write(data2, to: "logotemplate-image-using-imagemask.png")
		}
	}

	func testLogoQRMasking() throws {
		let doc = try QRCode.Document(
			utf8String: "Verifying logo image masking works",
			errorCorrection: .high
		)

		let path = CGPath(rect: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4), transform: nil)
		let transf = CGMutablePath()
		transf.addPath(path, transform: CGAffineTransform(scaleX: 10, y: 10))

		let outputFolder = try outputFolder.subfolder(with: "logotemplate-qrmasking")

		do {
			// Checking whether the logotemplate style of 'use path' correctly masks the qr accordingly
			let image = try resourceImage(for: "square-logo", extension: "png")
			let imageDestination = CGPath(rect: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4), transform: nil)
			do {
				doc.logoTemplate = QRCode.LogoTemplate(image: image, path: imageDestination)
				try outputFolder.write(try XCTUnwrap(doc.pngData(dimension: 300)), to: "logotemplate-imagepath-qrmasked.png")
				try outputFolder.write(try XCTUnwrap(doc.svgData(dimension: 300)), to: "logotemplate-imagepath-qrmasked.svg")
			}
			do {
				doc.logoTemplate = QRCode.LogoTemplate(image: image, path: imageDestination, masksQRCodePixels: false)
				try outputFolder.write(try XCTUnwrap(doc.pngData(dimension: 300)), to: "logotemplate-imagepath-qrnotmasked.png")
				try outputFolder.write(try XCTUnwrap(doc.svgData(dimension: 300)), to: "logotemplate-imagepath-qrnotmasked.svg")
			}
		}

		do {
			// Checking whether the logotemplate style of 'use images transparency' correctly masks the qr accordingly
			let image = try resourceImage(for: "logo", extension: "png")
			do {
				doc.logoTemplate = QRCode.LogoTemplate(image: image)
				try outputFolder.write(try XCTUnwrap(doc.pngData(dimension: 300)), to: "logotemplate-transparency-qrmasked.png")
				try outputFolder.write(try XCTUnwrap(doc.svgData(dimension: 300)), to: "logotemplate-transparency-qrmasked.svg")
			}
			do {
				doc.logoTemplate = QRCode.LogoTemplate(image: image, masksQRCodePixels: false)
				try outputFolder.write(try XCTUnwrap(doc.pngData(dimension: 300)), to: "logotemplate-transparency-qrnotmasked.png")
				try outputFolder.write(try XCTUnwrap(doc.svgData(dimension: 300)), to: "logotemplate-transparency-qrnotmasked.svg")
			}
		}

		do {
			// Checking whether the logotemplate style of 'use images transparency' correctly masks the qr accordingly
			let image = try resourceImage(for: "logo", extension: "png")
			let imagemask = try resourceImage(for: "logo-mask", extension: "png")
			do {
				doc.logoTemplate = QRCode.LogoTemplate(image: image, maskImage: imagemask)
				try outputFolder.write(try XCTUnwrap(doc.pngData(dimension: 300)), to: "logotemplate-maskimage-qrmasked.png")
				try outputFolder.write(try XCTUnwrap(doc.svgData(dimension: 300)), to: "logotemplate-maskimage-qrmasked.svg")
			}
			do {
				doc.logoTemplate = QRCode.LogoTemplate(image: image, maskImage: imagemask, masksQRCodePixels: false)
				try outputFolder.write(try XCTUnwrap(doc.pngData(dimension: 300)), to: "logotemplate-maskimage-qrnotmasked.png")
				try outputFolder.write(try XCTUnwrap(doc.svgData(dimension: 300)), to: "logotemplate-maskimage-qrnotmasked.svg")
			}
		}
	}

	func testIssue34Export() throws {

		let logoImage = try resourceImage(for: "instagram-icon", extension: "png")
		let logoTemplate = QRCode.LogoTemplate(
			image: logoImage,
			path: CGPath(ellipseIn: CGRect(x: 0.65, y: 0.35, width: 0.30, height: 0.30), transform: nil),
			inset: 8
		)

		let doc = try QRCode.build
			.text("This is checking issue 34 bug fix")
			.backgroundColor(CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1))
			.eye.shape(QRCode.EyeShape.Squircle())
			.logo(logoTemplate)
			.document

		try [0, 12].forEach { quietSpace in
			doc.design.additionalQuietZonePixels = UInt(quietSpace)

			let svgData = try doc.svgData(dimension: 400)
			try outputFolder.write(svgData, to: "logotemplate-issue34-\(quietSpace).svg")

			let pdfData = try doc.pdfData(dimension: 400)
			try outputFolder.write(pdfData, to: "logotemplate-issue34-\(quietSpace).pdf")

			let imageSame = try doc.cgImage(width: 400, height: 400)
			try outputFolder.write(try imageSame.imageData(for: .png()), to: "logotemplate-issue34-equal-\(quietSpace).png")

			let pdfSame = try doc.pdfData(width: 400, height: 400)
			try outputFolder.write(pdfSame, to: "logotemplate-issue34-equal-\(quietSpace).pdf")

			let imagewBigger = try doc.cgImage(width: 800, height: 400)
			try outputFolder.write(try imagewBigger.imageData(for: .png()), to: "logotemplate-issue34-width-bigger-\(quietSpace).png")

			let pdfwBigger = try doc.pdfData(width: 800, height: 400)
			try outputFolder.write(pdfwBigger, to: "logotemplate-issue34-width-bigger-\(quietSpace).pdf")

			let imagehBigger = try doc.cgImage(width: 400, height: 800)
			try outputFolder.write(try imagehBigger.imageData(for: .png()), to: "logotemplate-issue34-height-bigger-\(quietSpace).png")

			let pdfhBigger = try doc.pdfData(width: 400, height: 800)
			try outputFolder.write(pdfhBigger, to: "logotemplate-issue34-height-bigger-\(quietSpace).pdf")
		}
	}

	func testPathGenerationWithLogoTemplate() throws {

		// Check that generating a CGPath contains a hole for the logotemplate if it exists

		let outputFolder = try outputFolder.subfolder(with: "logo-path-check")

		let logoImage = try resourceImage(for: "instagram-icon", extension: "png")
		let logoTemplate = QRCode.LogoTemplate(
			image: logoImage,
			path: CGPath(ellipseIn: CGRect(x: 0.65, y: 0.35, width: 0.30, height: 0.30), transform: nil),
			inset: 8
		)

		let doc = try QRCode.build
			.text("Logo template checking with path export Logo template checking with path export Logo template checking with path export")
			.backgroundColor(CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1))
			.eye.shape(QRCode.EyeShape.Squircle())
			.document

		try [0, 12].forEach { quietSpace in
			doc.design.additionalQuietZonePixels = UInt(quietSpace)

			do {
				// No logotemplate
				doc.logoTemplate = nil
				let path = doc.path(dimension: 400)
				let b1 = try CreateBitmap(dimension: 400, backgroundColor: CGColor.commonWhite) { ctx in
					ctx.addPath(path)
					ctx.setFillColor(.commonBlack)
					ctx.fillPath()
				}
				try outputFolder.write(try b1.representation.png(), to: "path-without-logotemplate-\(quietSpace).png")
			}

			do {
				// No logotemplate
				doc.logoTemplate = logoTemplate
				let path = doc.path(dimension: 400)
				let b1 = try CreateBitmap(dimension: 400, backgroundColor: CGColor.commonWhite) { ctx in
					ctx.addPath(path)
					ctx.setFillColor(.commonBlack)
					ctx.fillPath()
				}
				try outputFolder.write(try b1.representation.png(), to: "path-with-logotemplate-\(quietSpace).png")
			}
		}
	}
}
