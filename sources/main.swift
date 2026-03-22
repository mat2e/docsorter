import Foundation

struct DocSorter {
    static func main() async throws {
        let args = [".", "/Users/matthias/Code/private/sample-input/impfe.pdf"] // CommandLine.arguments
        //guard args.count > 1 else { printUsage(); exit(1) }

        let config = try Config.load()
        let inputPaths = args.dropFirst().map { URL(fileURLWithPath: $0) }

        for inputURL in inputPaths {
            do {
                print("\nVerarbeite: \(inputURL.lastPathComponent)")
                try await processDocument(at: inputURL, config: config)
            } catch {
                print("  ✗ Fehler: \(error.localizedDescription)")
                AuditLog.write(
                    file: inputURL.lastPathComponent,
                    decision: "FEHLER",
                    reason: error.localizedDescription,
                    confidence: 0
                )
            }
        }
    }

    static func processDocument(at url: URL, config: Config) async throws {
        guard #available(macOS 26.0, *) else {
            throw NSError(domain: "docsorter", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "macOS 26 erforderlich"])
        }
      
        let inboxPath = url.deletingLastPathComponent()

        // 1. OCR
        print("  [1/4] OCR...")
        let ocrResult = try await OCRProcessor.process(pdfURL: url)

        // 2. Metadaten extrahieren
        print("  [2/4] Metadaten extrahieren...")
        let extractor = MetadataExtractor(config: config)
        let metadata = try await extractor.extract(
            from: ocrResult,
            inboxPath: inboxPath,
            sourceURL: url 
        )
        print("        Absender:  \(metadata.sender  ?? "–")")
        print("        Datum:     \(formatDate(metadata.date) ?? "–")")
        print("        Betreff:   \(metadata.subject  ?? "–")")
        print("        Thema:     \(metadata.topic    ?? "–")")
        print("        Empfänger: \(metadata.recipients.isEmpty ? "–" : metadata.recipients.joined(separator: ", "))")
        print("        Konfidenz: \(String(format: "%.0f%%", metadata.confidence.overall * 100))")

        // Audit bei niedriger Konfidenz
        if metadata.confidence.overall < config.confidence.auditThreshold {
            AuditLog.write(
                file: url.lastPathComponent,
                decision: "NIEDRIGE_KONFIDENZ",
                reason: "Konfidenz \(String(format: "%.0f%%", metadata.confidence.overall * 100)) unter Schwellwert",
                confidence: metadata.confidence.overall,
                metadata: metadata
            )
        }

        // 3. Tags setzen
        print("  [3/4] Tags setzen...")
        let workingURL = ocrResult.searchablePDFURL ?? url
        let tagSet = TagSet.from(metadata)
        try Tagger.apply(tags: tagSet, to: workingURL)

        // 4. Ablegen
        print("  [4/4] Ablegen...")
        let sorter = FileSorter(config: config)
        let result = try sorter.sort(
            fileURL: workingURL,
            metadata: metadata,
            inboxPath: inboxPath
        )

        print("  ✓ Fertig: \(result.destinationURL.lastPathComponent)")
    }

    static func formatDate(_ components: DateComponents?) -> String? {
        guard let c = components,
              let y = c.year, let m = c.month, let d = c.day
        else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func printUsage() {
        print("""
        docsorter – Dokumenten-Sortierer

        Verwendung:
          docsorter <datei.pdf> [datei2.pdf ...]

        Konfiguration: ~/.config/docsorter/config.json
        Protokoll:     ~/.config/docsorter/audit.log
        """)
    }
}

try await DocSorter.main()
