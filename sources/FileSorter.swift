//
//  SortResult.swift
//  
//
//  Created by Matthias Wronka on 22.03.26.
//


import Foundation

struct SortResult {
    let sourceURL: URL
    let destinationURL: URL
    let wasRenamed: Bool
}

struct FileSorter {

    private let config: Config

    init(config: Config) {
        self.config = config
    }

    // MARK: - Hauptmethode

    func sort(
        fileURL: URL,
        metadata: DocumentMetadata,
        inboxPath: URL?
    ) throws -> SortResult {

        // 1. Topic bestimmen (Metadata > Inbox-Ordner > Fallback)
        let topic = resolveTopic(metadata: metadata, inboxPath: inboxPath)

        // 2. Passende Output-Regel finden
        guard let rule = config.outputRule(for: topic ?? "Sonstiges") else {
            throw SortError.noMatchingRule(topic ?? "unbekannt")
        }

        // 3. Template auflösen
        let destinationURL = try resolveTemplate(
            rule.pathTemplate,
            metadata: metadata,
            topic: topic,
            fileURL: fileURL
        )

        // 4. Audit falls kritische Felder fehlen
        auditIfNeeded(
            fileURL: fileURL,
            metadata: metadata,
            topic: topic,
            destinationURL: destinationURL
        )

        // 5. Zielordner anlegen
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // 6. Konflikt behandeln
        let finalURL = resolveConflict(for: destinationURL)

      // 7. Datei verschieben oder kopieren
      if config.shouldKeepOriginals {
          try FileManager.default.copyItem(at: fileURL, to: finalURL)
          print("  → Kopiert (Original behalten): \(finalURL.path)")
      } else {
          try FileManager.default.moveItem(at: fileURL, to: finalURL)
          print("  → Verschoben: \(finalURL.path)")
      }

        return SortResult(
            sourceURL: fileURL,
            destinationURL: finalURL,
            wasRenamed: finalURL != destinationURL
        )
    }

    // MARK: - Topic auflösen

    private func resolveTopic(metadata: DocumentMetadata, inboxPath: URL?) -> String? {
        // 1. LLM-Ergebnis hat Vorrang
        if let topic = metadata.topic { return topic }

        // 2. Inbox-Ordner-Mapping als Fallback
        if let inboxPath {
            let expandedInbox = config.expandedInboxFolderToTopic()
            if let mapped = expandedInbox[inboxPath.path] {
                return mapped
            }
        }

        return nil
    }

    // MARK: - Template auflösen

    private func resolveTemplate(
        _ template: String,
        metadata: DocumentMetadata,
        topic: String?,
        fileURL: URL
    ) throws -> URL {

        let date = metadata.date
        let dateString = formatDate(date) ?? "undatiert"
        let year = date?.year.map { String($0) } ?? "unbekannt"

        // Empfänger: nur wenn genau einer → sonst "Mehrere"
        let recipient: String
        switch metadata.recipients.count {
        case 0: recipient = "Unbekannt"
        case 1: recipient = metadata.recipients[0]
        default: recipient = "Mehrere"
        }

        // Dateiname-sichere Strings erzeugen
        let sender  = sanitize(metadata.sender  ?? "Unbekannt")
        let subject = sanitize(metadata.subject ?? "Unbekannt")
        let topicSanitized = sanitize(topic ?? "Sonstiges")

        var path = template
            .replacingOccurrences(of: "{baseDir}",   with: config.expandedBaseOutputDir)
            .replacingOccurrences(of: "{topic}",     with: topicSanitized)
            .replacingOccurrences(of: "{year}",      with: year)
            .replacingOccurrences(of: "{date}",      with: dateString)
            .replacingOccurrences(of: "{sender}",    with: sender)
            .replacingOccurrences(of: "{subject}",   with: subject)
            .replacingOccurrences(of: "{recipient}", with: recipient)

        // Sicherstellen dass .pdf Endung vorhanden
        if !path.hasSuffix(".pdf") {
            path += ".pdf"
        }

        return URL(fileURLWithPath: path)
    }

    // MARK: - Konfliktbehandlung

    /// Falls Zieldatei existiert: Suffix _2, _3, ... anhängen
    private func resolveConflict(for url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return url
        }

        let base = url.deletingPathExtension()
        let ext  = url.pathExtension
        var counter = 2

        while true {
            let candidate = base
                .appendingPathExtension("_\(counter)")
                .appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    // MARK: - Audit

    private func auditIfNeeded(
        fileURL: URL,
        metadata: DocumentMetadata,
        topic: String?,
        destinationURL: URL
    ) {
        var reasons: [String] = []

        if metadata.date == nil       { reasons.append("Datum unbekannt") }
        if metadata.sender == nil     { reasons.append("Absender unbekannt") }
        if metadata.subject == nil    { reasons.append("Betreff unbekannt") }
        if topic == nil               { reasons.append("Thema unbekannt") }
        if metadata.recipients.count > 1 {
            reasons.append("Mehrere Empfänger: \(metadata.recipients.joined(separator: ", "))")
        }

        guard !reasons.isEmpty else { return }

        AuditLog.write(
            file: fileURL.lastPathComponent,
            decision: "ABLAGE_MIT_LÜCKEN",
            reason: reasons.joined(separator: "; "),
            confidence: metadata.confidence.overall,
            metadata: metadata
        )
    }

    // MARK: - Hilfsmethoden

    /// Datum als YYYY-MM-DD formatieren
    private func formatDate(_ components: DateComponents?) -> String? {
        guard let c = components,
              let year = c.year, let month = c.month, let day = c.day
        else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Dateiname-sichere Zeichen: Sonderzeichen ersetzen, Länge begrenzen
    private func sanitize(_ string: String) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(.init(charactersIn: "-_äöüÄÖÜß "))
        let sanitized = string
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map { Character($0) }
            .map { String($0) }
            .joined()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
        return String(sanitized.prefix(60))
    }
}

// MARK: - Fehler

enum SortError: LocalizedError {
    case noMatchingRule(String)

    var errorDescription: String? {
        switch self {
        case .noMatchingRule(let topic):
            return "Keine passende Output-Regel für Topic: \(topic)"
        }
    }
}
