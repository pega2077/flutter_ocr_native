import Flutter
import UIKit
import Vision

public class OcrPlugin: NSObject, FlutterPlugin {
    private let englishPattern = try! NSRegularExpression(pattern: "[A-Za-z0-9]")
    private let aadhaarPattern = try! NSRegularExpression(pattern: "(\\d{4})[\\s\\-]*(\\d{4})[\\s\\-]*(\\d{4})")
    private var languageMode: String?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.flutter_ocr_native/text_recognition", binaryMessenger: registrar.messenger())
        let instance = OcrPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {
        case "recognizeFromPath":
            guard let path = args?["imagePath"] as? String,
                  let uiImage = UIImage(contentsOfFile: path),
                  let cgImage = uiImage.cgImage else {
                result(FlutterError(code: "INVALID_ARG", message: "Invalid image path", details: nil))
                return
            }
            recognizeText(from: cgImage, result: result)

        case "recognizeFromBytes":
            guard let bytes = args?["bytes"] as? FlutterStandardTypedData,
                  let uiImage = UIImage(data: bytes.data),
                  let cgImage = uiImage.cgImage else {
                result(FlutterError(code: "INVALID_ARG", message: "Invalid image bytes", details: nil))
                return
            }
            recognizeText(from: cgImage, result: result)

        case "burnWatermark":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["imageBytes"] as? FlutterStandardTypedData,
                  let lines = args["lines"] as? [String: String],
                  let uiImage = UIImage(data: bytes.data) else {
                result(FlutterError(code: "INVALID_ARG", message: "imageBytes and lines required", details: nil))
                return
            }
            let quality = args["quality"] as? Int ?? 90
            let output = burnWatermarkOnImage(uiImage, lines: lines, quality: quality)
            result(output)

        case "compressImage":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["imageBytes"] as? FlutterStandardTypedData,
                  let uiImage = UIImage(data: bytes.data) else {
                result(FlutterError(code: "INVALID_ARG", message: "imageBytes required", details: nil))
                return
            }
            let quality = args["quality"] as? Int ?? 80
            let compressed = uiImage.jpegData(compressionQuality: CGFloat(quality) / 100.0)
            result(compressed.map { FlutterStandardTypedData(bytes: $0) })

        case "extractFace":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["imageBytes"] as? FlutterStandardTypedData,
                  let uiImage = UIImage(data: bytes.data),
                  let cgImage = uiImage.cgImage else {
                result(FlutterError(code: "INVALID_ARG", message: "imageBytes required", details: nil))
                return
            }
            extractFace(from: cgImage, result: result)

        case "cropImage":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["imageBytes"] as? FlutterStandardTypedData,
                  let uiImage = UIImage(data: bytes.data),
                  let cgImage = uiImage.cgImage else {
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
            let croppedImage = UIImage(cgImage: cropped)
            guard let jpegData = croppedImage.jpegData(compressionQuality: 0.9) else {
                result(nil)
                return
            }
            result(FlutterStandardTypedData(bytes: jpegData))

        case "rotateImage":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["imageBytes"] as? FlutterStandardTypedData,
                  let uiImage = UIImage(data: bytes.data) else {
                result(FlutterError(code: "INVALID_ARG", message: "imageBytes required", details: nil))
                return
            }
            let degrees = args["degrees"] as? Int ?? 90
            let radians = CGFloat(degrees) * .pi / 180.0
            let rotatedSize = CGSize(
                width: abs(uiImage.size.width * cos(radians)) + abs(uiImage.size.height * sin(radians)),
                height: abs(uiImage.size.width * sin(radians)) + abs(uiImage.size.height * cos(radians))
            )
            UIGraphicsBeginImageContextWithOptions(rotatedSize, false, 1.0)
            let context = UIGraphicsGetCurrentContext()!
            context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
            context.rotate(by: radians)
            uiImage.draw(in: CGRect(x: -uiImage.size.width / 2, y: -uiImage.size.height / 2, width: uiImage.size.width, height: uiImage.size.height))
            let rotated = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            guard let rotatedImg = rotated, let jpegRotated = rotatedImg.jpegData(compressionQuality: 0.9) else {
                result(nil)
                return
            }
            result(FlutterStandardTypedData(bytes: jpegRotated))

        case "correctOrientation":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["imageBytes"] as? FlutterStandardTypedData,
                  let uiImage = UIImage(data: bytes.data) else {
                result(FlutterError(code: "INVALID_ARG", message: "imageBytes required", details: nil))
                return
            }
            correctOrientation(uiImage: uiImage, originalBytes: bytes.data, result: result)

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
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

            // Scale and draw PDF page
            ctx.scaleBy(x: effectiveScale, y: effectiveScale)
            ctx.drawPDFPage(pdfPage)

            guard let cgImage = ctx.makeImage() else {
                DispatchQueue.main.async { result(nil) }
                return
            }

            let uiImage = UIImage(cgImage: cgImage)
            guard let jpegData = uiImage.jpegData(compressionQuality: 0.85) else {
                DispatchQueue.main.async { result(nil) }
                return
            }

            DispatchQueue.main.async {
                result(FlutterStandardTypedData(bytes: jpegData))
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
        // Must contain only ASCII printable characters
        guard text.allSatisfy({ $0.asciiValue != nil && $0.asciiValue! >= 32 && $0.asciiValue! <= 126 }) else {
            return false
        }

        // Must have at least one letter or digit
        guard text.contains(where: { $0.isLetter || $0.isNumber }) else {
            return false
        }

        // For words with 4+ letters, must contain a vowel
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

    private func jpegData(from image: UIImage, quality: CGFloat, fallback: Data) -> FlutterStandardTypedData {
        guard let jpeg = image.jpegData(compressionQuality: quality) else {
            return FlutterStandardTypedData(bytes: fallback)
        }
        return FlutterStandardTypedData(bytes: jpeg)
    }

    private func rotateImage(_ image: UIImage, degrees: Int) -> UIImage {
        let radians = CGFloat(degrees) * .pi / 180.0
        let w = image.size.width
        let h = image.size.height
        let newSize = CGSize(
            width: abs(w * cos(radians)) + abs(h * sin(radians)),
            height: abs(w * sin(radians)) + abs(h * cos(radians))
        )
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: newSize, format: fmt)
        return renderer.image { ctx in
            ctx.cgContext.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            ctx.cgContext.rotate(by: radians)
            image.draw(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        }
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
        uiImage: UIImage,
        originalBytes: Data,
        result: @escaping FlutterResult
    ) {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: uiImage.size, format: fmt)
        let normalized = renderer.image { _ in uiImage.draw(at: .zero) }
        guard let cgBase = normalized.cgImage else {
            result(FlutterStandardTypedData(bytes: originalBytes))
            return
        }

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
                    result(self.jpegData(from: normalized, quality: 0.95, fallback: originalBytes))
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
                    result(self.jpegData(from: normalized, quality: 0.95, fallback: originalBytes))
                } else {
                    let rotatedImage = self.rotateImage(normalized, degrees: bestDegrees)
                    result(self.jpegData(from: rotatedImage, quality: 0.95, fallback: originalBytes))
                }
            }
        }
    }

    private func recognizeText(from image: CGImage, result: @escaping FlutterResult) {
        let filterLatinOnly = shouldFilterLatinOnly()
        let languageTag = recognizedLanguageTag()
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                result(FlutterError(code: "RECOGNITION_FAILED", message: error.localizedDescription, details: nil))
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
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

        // Find observation containing Aadhaar number
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

            // Calculate proportional mask area (first 8 digits)
            let matchRange = match.range
            let last4Range = match.range(at: 3)
            let charWidth = obsRect.width / CGFloat(nsText.length)

            let maskLeft = obsRect.origin.x + CGFloat(matchRange.location) * charWidth
            let maskRight = obsRect.origin.x + CGFloat(last4Range.location) * charWidth

            maskRect = CGRect(
                x: maskLeft,
                y: obsRect.origin.y,
                width: maskRight - maskLeft,
                height: obsRect.height
            )
            break
        }

        guard let rect = maskRect else { return nil }

        // Draw mask on image
        let size = CGSize(width: imageWidth, height: imageHeight)
        UIGraphicsBeginImageContext(size)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }

        // Flip context for CGImage drawing
        ctx.translateBy(x: 0, y: imageHeight)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: size))

        // Flip back for rect drawing
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: 0, y: -imageHeight)

        // Draw black rectangle with padding
        let padX = rect.width * 0.03
        let padY = rect.height * 0.1
        let paddedRect = CGRect(
            x: max(rect.origin.x - padX, 0),
            y: max(rect.origin.y - padY, 0),
            width: min(rect.width + padX * 2, imageWidth),
            height: min(rect.height + padY * 2, imageHeight)
        )
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(paddedRect)

        guard let maskedImage = UIGraphicsGetImageFromCurrentImageContext(),
              let jpegData = maskedImage.jpegData(compressionQuality: 0.9) else {
            UIGraphicsEndImageContext()
            return nil
        }
        UIGraphicsEndImageContext()

        return FlutterStandardTypedData(bytes: jpegData)
    }

    private func detectPrinted(observations: [VNRecognizedTextObservation]) -> Bool {
        if observations.isEmpty { return false }

        // Exclude MICR-like observations: bottom of image, mostly digits, low confidence
        let filtered = observations.filter { obs in
            let isAtBottom = obs.boundingBox.origin.y < 0.25 // Vision uses bottom-left origin
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

        let avgConfidence = Double(confidences.reduce(0, +)) / Double(confidences.count)
        let lowConfCount = confidences.filter { $0 < 0.5 }.count
        let lowConfRatio = Double(lowConfCount) / Double(confidences.count)

        let score = (avgConfidence * 0.5) + ((1.0 - lowConfRatio) * 0.5)
        return score > 0.45
    }

    private func burnWatermarkOnImage(_ image: UIImage, lines: [String: String],
        quality: Int) -> FlutterStandardTypedData? {

        let scaledFontSize = max(image.size.width * 0.03, 36)
        let scaledPadH = image.size.width * 0.02
        let scaledPadV = image.size.width * 0.015
        let lineHeight = scaledFontSize * 1.5
        let wmHeight = CGFloat(lines.count) * lineHeight + scaledPadV * 2
        let totalSize = CGSize(width: image.size.width, height: image.size.height + wmHeight)

        UIGraphicsBeginImageContextWithOptions(totalSize, false, image.scale)
        guard UIGraphicsGetCurrentContext() != nil else { return nil }

        image.draw(at: .zero)

        UIColor(red: 0, green: 0, blue: 0, alpha: 0.7).setFill()
        UIRectFill(CGRect(x: 0, y: image.size.height, width: totalSize.width, height: wmHeight))

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: scaledFontSize),
            .foregroundColor: UIColor(red: 1, green: 1, blue: 1, alpha: 0.8)
        ]
        var y = image.size.height + scaledPadV
        for (key, value) in lines {
            let text = "\(key): \(value)" as NSString
            text.draw(at: CGPoint(x: scaledPadH, y: y), withAttributes: attrs)
            y += lineHeight
        }

        guard let output = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        UIGraphicsEndImageContext()

        let data: Data?
        if quality < 100 {
            data = output.jpegData(compressionQuality: CGFloat(quality) / 100.0)
        } else {
            data = output.pngData()
        }
        guard let finalData = data else { return nil }
        return FlutterStandardTypedData(bytes: finalData)
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

        let uiImage = UIImage(cgImage: cropped)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.9) else {
            return nil
        }
        return FlutterStandardTypedData(bytes: jpegData)
    }

    private func extractFace(from image: CGImage, result: @escaping FlutterResult) {
        let request = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                result(FlutterError(code: "FACE_DETECTION_FAILED", message: error.localizedDescription, details: nil))
                return
            }

            guard let faces = request.results as? [VNFaceObservation], !faces.isEmpty else {
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
