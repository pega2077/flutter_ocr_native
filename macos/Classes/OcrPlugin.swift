import Cocoa
import FlutterMacOS
import Vision

public class OcrPlugin: NSObject, FlutterPlugin {
    private let englishPattern = try! NSRegularExpression(pattern: "[A-Za-z0-9]")
    private let aadhaarPattern = try! NSRegularExpression(pattern: "(\\d{4})[\\s\\-]*(\\d{4})[\\s\\-]*(\\d{4})")
    private var languageMode: String?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.flutter_ocr_native/text_recognition", binaryMessenger: registrar.messenger)
        let instance = OcrPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {
        case "recognizeFromPath":
            guard let path = args?["imagePath"] as? String,
                  let nsImage = NSImage(contentsOfFile: path),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                result(FlutterError(code: "INVALID_ARG", message: "Invalid image path", details: nil))
                return
            }
            recognizeText(from: cgImage, result: result)

        case "recognizeFromBytes":
            guard let bytes = args?["bytes"] as? FlutterStandardTypedData,
                  let nsImage = NSImage(data: bytes.data),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                result(FlutterError(code: "INVALID_ARG", message: "Invalid image bytes", details: nil))
                return
            }
            recognizeText(from: cgImage, result: result)

        case "burnWatermark":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["imageBytes"] as? FlutterStandardTypedData,
                  let lines = args["lines"] as? [String: String],
                  let nsImage = NSImage(data: bytes.data) else {
                result(FlutterError(code: "INVALID_ARG", message: "imageBytes and lines required", details: nil))
                return
            }
            let quality = args["quality"] as? Int ?? 90
            let output = burnWatermarkOnImage(nsImage, lines: lines, quality: quality)
            result(output)

        case "compressImage":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["imageBytes"] as? FlutterStandardTypedData,
                  let nsImage = NSImage(data: bytes.data) else {
                result(FlutterError(code: "INVALID_ARG", message: "imageBytes required", details: nil))
                return
            }
            let quality = args["quality"] as? Int ?? 80
            let compressed = compressToJpeg(nsImage, quality: quality)
            result(compressed)

        case "extractFace":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["imageBytes"] as? FlutterStandardTypedData,
                  let nsImage = NSImage(data: bytes.data),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                result(FlutterError(code: "INVALID_ARG", message: "imageBytes required", details: nil))
                return
            }
            extractFace(from: cgImage, result: result)

        case "cropImage":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["imageBytes"] as? FlutterStandardTypedData,
                  let nsImage = NSImage(data: bytes.data),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                result(FlutterError(code: "INVALID_ARG", message: "imageBytes required", details: nil))
                return
            }
            let x = args["x"] as? Int ?? 0
            let y = args["y"] as? Int ?? 0
            let width = args["width"] as? Int ?? 0
            let height = args["height"] as? Int ?? 0
            let cropRect = CGRect(x: x, y: y, width: width, height: height)
            guard let cropped = cgImage.cropping(to: cropRect) else {
                result(nil)
                return
            }
            let size = NSSize(width: cropped.width, height: cropped.height)
            let croppedNS = NSImage(cgImage: cropped, size: size)
            guard let tiff = croppedNS.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                result(nil)
                return
            }
            result(FlutterStandardTypedData(bytes: jpeg))

        case "rotateImage":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["imageBytes"] as? FlutterStandardTypedData,
                  let nsImage = NSImage(data: bytes.data) else {
                result(FlutterError(code: "INVALID_ARG", message: "imageBytes required", details: nil))
                return
            }
            let degrees = args["degrees"] as? Int ?? 90
            let radians = CGFloat(degrees) * .pi / 180.0
            let srcSize = nsImage.size
            let newSize = NSSize(
                width: abs(srcSize.width * cos(radians)) + abs(srcSize.height * sin(radians)),
                height: abs(srcSize.width * sin(radians)) + abs(srcSize.height * cos(radians))
            )
            let rotatedImage = NSImage(size: newSize)
            rotatedImage.lockFocus()
            let transform = NSAffineTransform()
            transform.translateX(by: newSize.width / 2, yBy: newSize.height / 2)
            transform.rotate(byDegrees: CGFloat(degrees))
            transform.translateX(by: -srcSize.width / 2, yBy: -srcSize.height / 2)
            transform.concat()
            nsImage.draw(in: NSRect(origin: .zero, size: srcSize))
            rotatedImage.unlockFocus()
            guard let tiff = rotatedImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                result(nil)
                return
            }
            result(FlutterStandardTypedData(bytes: jpeg))

        case "correctOrientation":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["imageBytes"] as? FlutterStandardTypedData,
                  let nsImage = NSImage(data: bytes.data),
                  let cgBase = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                result(FlutterError(code: "INVALID_ARG", message: "imageBytes required", details: nil))
                return
            }
            correctOrientation(nsImage: nsImage, cgBase: cgBase, originalBytes: bytes.data, result: result)

        case "setLanguage":
            guard let languageTag = args?["languageTag"] as? String, !languageTag.isEmpty else {
                result(FlutterError(code: "INVALID_ARG", message: "languageTag required", details: nil))
                return
            }
            languageMode = languageTag
            result(nil)

        case "dispose":
            result(nil)

        case "renderPdfPage":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["pdfBytes"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARG", message: "pdfBytes required", details: nil))
                return
            }
            let page = args["page"] as? Int ?? 0
            let scale = args["scale"] as? Double ?? 2.0
            renderPdfPage(data: bytes.data, page: page, scale: CGFloat(scale), result: result)

        case "getPdfPageCount":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["pdfBytes"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARG", message: "pdfBytes required", details: nil))
                return
            }
            let count = getPdfPageCount(data: bytes.data)
            result(count)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func renderPdfPage(data: Data, page: Int, scale: CGFloat, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let provider = CGDataProvider(data: data as CFData),
                  let document = CGPDFDocument(provider) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "PDF_READ_FAILED", message: "Cannot open PDF", details: nil))
                }
                return
            }

            guard let pdfPage = document.page(at: page + 1) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "INVALID_ARG", message: "Page \(page) not found", details: nil))
                }
                return
            }

            let pageRect = pdfPage.getBoxRect(.mediaBox)
            // Cap to prevent memory issues
            let maxDim: CGFloat = 3000
            let effectiveScale: CGFloat
            let rawW = pageRect.width * scale
            let rawH = pageRect.height * scale
            if rawW > maxDim || rawH > maxDim {
                effectiveScale = min(maxDim / pageRect.width, maxDim / pageRect.height)
            } else {
                effectiveScale = scale
            }

            let width = Int(pageRect.width * effectiveScale)
            let height = Int(pageRect.height * effectiveScale)

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(data: nil, width: width, height: height,
                                       bitsPerComponent: 8, bytesPerRow: width * 4,
                                       space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                DispatchQueue.main.async { result(nil) }
                return
            }

            // White background
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

            ctx.scaleBy(x: effectiveScale, y: effectiveScale)
            ctx.drawPDFPage(pdfPage)

            guard let cgImage = ctx.makeImage() else {
                DispatchQueue.main.async { result(nil) }
                return
            }

            let size = NSSize(width: width, height: height)
            let nsImage = NSImage(cgImage: cgImage, size: size)
            guard let tiff = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
                DispatchQueue.main.async { result(nil) }
                return
            }

            DispatchQueue.main.async {
                result(FlutterStandardTypedData(bytes: jpeg))
            }
        }
    }

    private func getPdfPageCount(data: Data) -> Int {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else {
            return 0
        }
        return document.numberOfPages
    }

    private func isEnglish(_ text: String) -> Bool {
        guard text.allSatisfy({ $0.asciiValue != nil && $0.asciiValue! >= 32 && $0.asciiValue! <= 126 }) else {
            return false
        }
        guard text.contains(where: { $0.isLetter || $0.isNumber }) else {
            return false
        }
        let letters = text.filter { $0.isLetter }
        if letters.count >= 4 {
            let vowels = CharacterSet(charactersIn: "aeiouAEIOU")
            let hasVowel = letters.unicodeScalars.contains(where: { vowels.contains($0) })
            if !hasVowel { return false }
        }
        return true
    }

    private func recognitionLanguages() -> [String] {
        if let mode = languageMode {
            if mode == "system" {
                return Array(Locale.preferredLanguages.prefix(3))
            }
            return [mode]
        }
        return ["en-US"]
    }

    private func shouldFilterLatinOnly() -> Bool {
        guard let mode = languageMode else { return true }
        if mode == "system" {
            return (Locale.preferredLanguages.first ?? "en-US").hasPrefix("en")
        }
        return mode.hasPrefix("en")
    }

    private func recognizedLanguageTag() -> String {
        if let mode = languageMode {
            if mode == "system" {
                return Locale.preferredLanguages.first ?? "en-US"
            }
            return mode
        }
        return "en-US"
    }

    private func textRecognitionScore(from observations: [VNRecognizedTextObservation]) -> Float {
        var score: Float = 0
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            score += observation.confidence * Float(candidate.string.count)
        }
        return score
    }

    private func jpegData(from image: NSImage, quality: CGFloat, fallback: Data) -> FlutterStandardTypedData {
        guard let tiff = image.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let jpeg = bmp.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            return FlutterStandardTypedData(bytes: fallback)
        }
        return FlutterStandardTypedData(bytes: jpeg)
    }

    private func rotateImage(_ image: NSImage, degrees: Int) -> NSImage {
        let radians = CGFloat(degrees) * .pi / 180.0
        let srcSize = image.size
        let newSize = NSSize(
            width: abs(srcSize.width * cos(radians)) + abs(srcSize.height * sin(radians)),
            height: abs(srcSize.width * sin(radians)) + abs(srcSize.height * cos(radians))
        )
        let rotatedImage = NSImage(size: newSize)
        rotatedImage.lockFocus()
        let transform = NSAffineTransform()
        transform.translateX(by: newSize.width / 2, yBy: newSize.height / 2)
        transform.rotate(byDegrees: CGFloat(degrees))
        transform.translateX(by: -srcSize.width / 2, yBy: -srcSize.height / 2)
        transform.concat()
        image.draw(in: NSRect(origin: .zero, size: srcSize))
        rotatedImage.unlockFocus()
        return rotatedImage
    }

    private func rotatedCGImage(from cgImage: CGImage, degrees: Int) -> CGImage? {
        let radians = CGFloat(degrees) * .pi / 180.0
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let newW = abs(w * cos(radians)) + abs(h * sin(radians))
        let newH = abs(w * sin(radians)) + abs(h * cos(radians))
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: Int(newW),
            height: Int(newH),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.translateBy(x: newW / 2, y: newH / 2)
        ctx.rotate(by: radians)
        ctx.draw(cgImage, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        return ctx.makeImage()
    }

    private func correctOrientation(
        nsImage: NSImage,
        cgBase: CGImage,
        originalBytes: Data,
        result: @escaping FlutterResult
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let originalRequest = VNRecognizeTextRequest()
            originalRequest.recognitionLevel = VNRequestTextRecognitionLevel.fast
            let originalHandler = VNImageRequestHandler(cgImage: cgBase, options: [:])
            try? originalHandler.perform([originalRequest])
            let originalObs = (originalRequest.results as? [VNRecognizedTextObservation]) ?? []
            let originalScore = self.textRecognitionScore(from: originalObs)

            if originalObs.count >= 2 && originalScore > 5.0 {
                DispatchQueue.main.async {
                    result(self.jpegData(from: nsImage, quality: 0.95, fallback: originalBytes))
                }
                return
            }

            let otherRotations: [Int] = [90, 180, 270]
            var bestDegrees = 0
            var bestScore = originalScore
            let group = DispatchGroup()
            let lock = NSLock()

            for deg in otherRotations {
                group.enter()
                guard let rotated = self.rotatedCGImage(from: cgBase, degrees: deg) else {
                    group.leave()
                    continue
                }

                let request = VNRecognizeTextRequest { req, _ in
                    let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                    let score = self.textRecognitionScore(from: observations)
                    lock.lock()
                    if score > bestScore {
                        bestScore = score
                        bestDegrees = deg
                    }
                    lock.unlock()
                    group.leave()
                }
                request.recognitionLevel = VNRequestTextRecognitionLevel.fast
                let handler = VNImageRequestHandler(cgImage: rotated, options: [:])
                try? handler.perform([request])
            }

            group.wait()
            DispatchQueue.main.async {
                if bestDegrees == 0 {
                    result(self.jpegData(from: nsImage, quality: 0.95, fallback: originalBytes))
                } else {
                    let rotatedImage = self.rotateImage(nsImage, degrees: bestDegrees)
                    result(self.jpegData(from: rotatedImage, quality: 0.95, fallback: originalBytes))
                }
            }
        }
    }

    private func recognizeText(from image: CGImage, result: @escaping FlutterResult) {
        let filterLatinOnly = shouldFilterLatinOnly()
        let languageTag = recognizedLanguageTag()
        let request = VNRecognizeTextRequest { [weak self] vnRequest, error in
            guard let self = self else { return }

            if let error = error {
                result(FlutterError(code: "RECOGNITION_FAILED", message: error.localizedDescription, details: nil))
                return
            }

            guard let observations = vnRequest.results as? [VNRecognizedTextObservation] else {
                result(["text": "", "blocks": [], "isPrinted": false, "maskedImageBytes": NSNull()])
                return
            }

            let imageWidth = CGFloat(image.width)
            let imageHeight = CGFloat(image.height)
            var blocks: [[String: Any]] = []

            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { continue }
                if filterLatinOnly && !self.isEnglish(text) { continue }

                let box = observation.boundingBox
                let boundingBox: [String: Any] = [
                    "left": box.origin.x * imageWidth,
                    "top": (1 - box.origin.y - box.height) * imageHeight,
                    "width": box.width * imageWidth,
                    "height": box.height * imageHeight
                ]

                let element: [String: Any] = [
                    "text": text,
                    "boundingBox": boundingBox,
                    "confidence": candidate.confidence
                ]

                let line: [String: Any] = [
                    "text": text,
                    "boundingBox": boundingBox,
                    "confidence": candidate.confidence,
                    "elements": [element]
                ]

                blocks.append([
                    "text": text,
                    "boundingBox": boundingBox,
                    "recognizedLanguage": languageTag,
                    "lines": [line]
                ])
            }

            let fullText = blocks.map { $0["text"] as? String ?? "" }.joined(separator: "\n")
            let isPrinted = self.detectPrinted(observations: observations)
            let maskedBytes = self.maskAadhaarOnImage(image: image, observations: observations)

            result([
                "text": fullText,
                "blocks": blocks,
                "isPrinted": isPrinted,
                "maskedImageBytes": maskedBytes as Any
            ])
        }

        request.recognitionLevel = VNRequestTextRecognitionLevel.accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = recognitionLanguages()

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                result(FlutterError(code: "RECOGNITION_FAILED", message: error.localizedDescription, details: nil))
            }
        }
    }

    private func maskAadhaarOnImage(image: CGImage, observations: [VNRecognizedTextObservation]) -> FlutterStandardTypedData? {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        var maskRect: CGRect? = nil

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            guard let match = aadhaarPattern.firstMatch(in: text, range: range) else { continue }

            let box = observation.boundingBox
            let obsRect = CGRect(
                x: box.origin.x * imageWidth,
                y: (1 - box.origin.y - box.height) * imageHeight,
                width: box.width * imageWidth,
                height: box.height * imageHeight
            )

            let last4Range = match.range(at: 3)
            let charWidth = obsRect.width / CGFloat(nsText.length)
            let maskLeft = obsRect.origin.x + CGFloat(match.range.location) * charWidth
            let maskRight = obsRect.origin.x + CGFloat(last4Range.location) * charWidth

            maskRect = CGRect(x: maskLeft, y: obsRect.origin.y, width: maskRight - maskLeft, height: obsRect.height)
            break
        }

        guard let rect = maskRect else { return nil }

        let size = NSSize(width: imageWidth, height: imageHeight)
        let nsImage = NSImage(size: size)
        nsImage.lockFocus()

        let ctx = NSGraphicsContext.current!.cgContext
        ctx.draw(image, in: CGRect(origin: .zero, size: size))

        let padX = rect.width * 0.03
        let padY = rect.height * 0.1
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(
            x: max(rect.origin.x - padX, 0),
            y: max(rect.origin.y - padY, 0),
            width: min(rect.width + padX * 2, imageWidth),
            height: min(rect.height + padY * 2, imageHeight)
        ))

        nsImage.unlockFocus()

        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            return nil
        }
        return FlutterStandardTypedData(bytes: jpeg)
    }

    private func detectPrinted(observations: [VNRecognizedTextObservation]) -> Bool {
        if observations.isEmpty { return false }

        // Exclude MICR-like observations: bottom of image, mostly digits, low confidence
        let filtered = observations.filter { obs in
            let isAtBottom = obs.boundingBox.origin.y < 0.25
            let text = obs.topCandidates(1).first?.string ?? ""
            let digitRatio = text.isEmpty ? 0.0 : Double(text.filter { $0.isNumber }.count) / Double(text.count)
            let isMostlyDigits = digitRatio > 0.6
            let confidence = obs.topCandidates(1).first?.confidence ?? 1.0
            let isLowConf = confidence < 0.5
            return !(isAtBottom && isMostlyDigits && isLowConf)
        }

        if filtered.isEmpty { return true }

        let confidences = filtered.compactMap { $0.topCandidates(1).first?.confidence }
        if confidences.isEmpty { return true }
        let avg = Double(confidences.reduce(0, +)) / Double(confidences.count)
        let lowCount = confidences.filter { $0 < 0.5 }.count
        let lowRatio = Double(lowCount) / Double(confidences.count)
        return (avg * 0.5 + (1.0 - lowRatio) * 0.5) > 0.45
    }

    private func burnWatermarkOnImage(_ image: NSImage, lines: [String: String], quality: Int) -> FlutterStandardTypedData? {
        let scaledFontSize = max(image.size.width * 0.03, 36)
        let scaledPadH = image.size.width * 0.02
        let scaledPadV = image.size.width * 0.015
        let lineHeight = scaledFontSize * 1.5
        let wmHeight = CGFloat(lines.count) * lineHeight + scaledPadV * 2
        let totalSize = NSSize(width: image.size.width, height: image.size.height + wmHeight)

        let outputImage = NSImage(size: totalSize)
        outputImage.lockFocus()

        image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)

        NSColor(red: 0, green: 0, blue: 0, alpha: 0.7).setFill()
        NSRect(x: 0, y: 0, width: totalSize.width, height: wmHeight).fill()

        // Note: macOS coordinate system is flipped (origin bottom-left)
        // Draw watermark at the bottom
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: scaledFontSize),
            .foregroundColor: NSColor(red: 1, green: 1, blue: 1, alpha: 0.8)
        ]
        var y = scaledPadV
        for (key, value) in lines {
            let text = "\(key): \(value)" as NSString
            text.draw(at: NSPoint(x: scaledPadH, y: y), withAttributes: attrs)
            y += lineHeight
        }

        outputImage.unlockFocus()

        guard let tiff = outputImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }

        let data: Data?
        if quality < 100 {
            data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: CGFloat(quality) / 100.0])
        } else {
            data = bitmap.representation(using: .png, properties: [:])
        }
        guard let finalData = data else { return nil }
        return FlutterStandardTypedData(bytes: finalData)
    }

    private func compressToJpeg(_ image: NSImage, quality: Int) -> FlutterStandardTypedData? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: CGFloat(quality) / 100.0]) else {
            return nil
        }
        return FlutterStandardTypedData(bytes: jpeg)
    }

    private func cropLargestFace(from image: CGImage, faces: [VNFaceObservation]) -> FlutterStandardTypedData? {
        guard let face = faces.max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }) else {
            return nil
        }

        let box = face.boundingBox
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)

        let faceX = box.origin.x * imageWidth
        let faceY = (1 - box.origin.y - box.height) * imageHeight
        let faceW = box.width * imageWidth
        let faceH = box.height * imageHeight

        let padX = faceW * 0.2
        let padY = faceH * 0.3
        let cropRect = CGRect(
            x: max(faceX - padX, 0),
            y: max(faceY - padY, 0),
            width: min(faceW + padX * 2, imageWidth),
            height: min(faceH + padY * 2, imageHeight)
        )

        guard let cropped = image.cropping(to: cropRect) else {
            return nil
        }

        let size = NSSize(width: cropped.width, height: cropped.height)
        let nsImage = NSImage(cgImage: cropped, size: size)
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            return nil
        }
        return FlutterStandardTypedData(bytes: jpeg)
    }

    private func extractFace(from image: CGImage, result: @escaping FlutterResult) {
        let request = VNDetectFaceRectanglesRequest { [weak self] vnRequest, error in
            guard let self = self else { return }

            if let error = error {
                result(FlutterError(code: "FACE_DETECTION_FAILED", message: error.localizedDescription, details: nil))
                return
            }

            guard let faces = vnRequest.results as? [VNFaceObservation], !faces.isEmpty else {
                result(nil)
                return
            }

            result(self.cropLargestFace(from: image, faces: faces))
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                result(FlutterError(code: "FACE_DETECTION_FAILED", message: error.localizedDescription, details: nil))
            }
        }
    }
}
