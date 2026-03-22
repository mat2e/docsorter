//
//  OCRResult.swift
//  
//
//  Created by Matthias Wronka on 22.03.26.
//


import Foundation
import PDFKit
import Vision
import CoreImage

struct OCRResult {
    let text: String                    // Volltext aller Seiten
    let pageTexts: [String]             // Text pro Seite
    let searchablePDFURL: URL?          // Neu erzeugtes durchsuchbares PDF (nil wenn Original schon Text hatte)
    let confidence: Double              // Durchschnittliche OCR-Konfidenz
}

struct OCRProcessor {

    // MARK: - Einstiegspunkt

    static func process(pdfURL: URL) async throws -> OCRResult {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            throw OCRError.cannotOpenPDF(pdfURL.path)
        }

        let pageCount = pdfDocument.pageCount
        guard pageCount > 0 else {
            throw OCRError.emptyPDF
        }

        // Prüfen ob PDF bereits Textebenen hat
        if hasTextLayer(pdfDocument) {
            let pageTexts = extractTextFromLayers(pdfDocument)
            let fullText = pageTexts.joined(separator: "\n\n")
            print("  → Textebene gefunden, OCR übersprungen")
            return OCRResult(
                text: fullText,
                pageTexts: pageTexts,
                searchablePDFURL: nil,
                confidence: 1.0
            )
        }

        // Kein Text → OCR durchführen
        print("  → Kein Text gefunden, starte OCR (\(pageCount) Seiten)...")
        return try await performOCR(on: pdfDocument, sourceURL: pdfURL)
    }

    // MARK: - Textebene prüfen

    private static func hasTextLayer(_ document: PDFDocument) -> Bool {
        // Erste drei Seiten prüfen (Heuristik)
        let pagesToCheck = min(3, document.pageCount)
        var totalChars = 0
        for i in 0..<pagesToCheck {
            totalChars += document.page(at: i)?.string?.count ?? 0
        }
        return totalChars > 50  // Weniger als 50 Zeichen = wahrscheinlich kein echter Text
    }

    private static func extractTextFromLayers(_ document: PDFDocument) -> [String] {
        (0..<document.pageCount).map { i in
            document.page(at: i)?.string ?? ""
        }
    }

    // MARK: - OCR mit Vision

    private static func performOCR(
        on document: PDFDocument,
        sourceURL: URL
    ) async throws -> OCRResult {

        var pageTexts: [String] = []
        var allConfidences: [Float] = []
        var pageImages: [CGImage] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            // Seite als Bild rastern
            let image = rasterize(page: page)
            pageImages.append(image)

            // Vision OCR
            let (text, confidences) = try await recognizeText(in: image)
            pageTexts.append(text)
            allConfidences.append(contentsOf: confidences)

            print("  → Seite \(pageIndex + 1)/\(document.pageCount) fertig")
        }

        // Durchsuchbares PDF erzeugen
        let outputURL = try buildSearchablePDF(
            sourceURL: sourceURL,
            pageTexts: pageTexts,
            pageImages: pageImages
        )

        let avgConfidence = allConfidences.isEmpty
            ? 0.0
            : Double(allConfidences.reduce(0, +) / Float(allConfidences.count))

        return OCRResult(
            text: pageTexts.joined(separator: "\n\n"),
            pageTexts: pageTexts,
            searchablePDFURL: outputURL,
            confidence: avgConfidence
        )
    }

    // MARK: - Seite rastern

    private static func rasterize(page: PDFPage, dpi: CGFloat = 200) -> CGImage {
        let bounds = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!

        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)

        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        page.draw(with: .mediaBox, to: context)
        NSGraphicsContext.current = nil

        return context.makeImage()!
    }

    // MARK: - Vision Text-Erkennung

    private static func recognizeText(in image: CGImage) async throws -> (String, [Float]) {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first }
                let text = lines.map(\.string).joined(separator: "\n")
                let confidences = lines.map(\.confidence)

                continuation.resume(returning: (text, confidences))
            }

            // Deutsch als primäre Sprache, Englisch als Fallback
            request.recognitionLanguages = ["de-DE", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Durchsuchbares PDF erzeugen

    private static func buildSearchablePDF(
        sourceURL: URL,
        pageTexts: [String],
        pageImages: [CGImage]
    ) throws -> URL {
        // Ausgabe neben Original, mit Suffix _ocr
        let outputURL = sourceURL
            .deletingPathExtension()
            .appendingPathExtension("_ocr")
            .appendingPathExtension("pdf")

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else {
            throw OCRError.cannotCreatePDF
        }

        for (index, image) in pageImages.enumerated() {
            let width = CGFloat(image.width)
            let height = CGFloat(image.height)
            var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)

            context.beginPage(mediaBox: &mediaBox)

            // Bild zeichnen
            context.draw(image, in: mediaBox)

            // Unsichtbaren Text als Ebene darüberlegen
            let text = pageTexts[index]
            let lines = text.components(separatedBy: "\n")
            let lineHeight = height / CGFloat(max(lines.count, 1))

            for (lineIndex, line) in lines.enumerated() {
                guard !line.isEmpty else { continue }
                let y = height - CGFloat(lineIndex + 1) * lineHeight
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: lineHeight * 0.8),
                    .foregroundColor: NSColor.clear  // Unsichtbar!
                ]
                let attrString = NSAttributedString(string: line, attributes: attributes)
                attrString.draw(at: CGPoint(x: 10, y: y))
            }

            context.endPage()
        }

        context.closePDF()

        try pdfData.write(to: outputURL, options: .atomic)
        print("  → Durchsuchbares PDF gespeichert: \(outputURL.lastPathComponent)")
        return outputURL
    }
}

// MARK: - Fehler

enum OCRError: LocalizedError {
    case cannotOpenPDF(String)
    case emptyPDF
    case cannotCreatePDF

    var errorDescription: String? {
        switch self {
        case .cannotOpenPDF(let path): return "PDF kann nicht geöffnet werden: \(path)"
        case .emptyPDF:                return "PDF enthält keine Seiten"
        case .cannotCreatePDF:         return "Durchsuchbares PDF kann nicht erstellt werden"
        }
    }
}
