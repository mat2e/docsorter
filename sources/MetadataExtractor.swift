import Foundation
import FoundationModels

// MARK: - Ergebnis-Typen

struct DocumentMetadata {
    let date: DateComponents?       // Erstellungsdatum des Dokuments
    let sender: String?             // Absender / Unternehmen
    let subject: String?            // Betreff / Titel
    let topic: String?              // Themenbereich (aus Config-Liste)
    let recipients: [String]        // Gefundene Familienmitglieder (shortNames)
    let confidence: MetadataConfidence
}

struct MetadataConfidence {
    let date: Double
    let sender: Double
    let subject: Double
    let topic: Double
    let overall: Double             // Durchschnitt, für Audit-Entscheidung
}

// MARK: - Structured Output Schema

/// Das Modell füllt diese Struktur direkt aus
@Generable
struct ExtractedMetadata: Codable {
    @Guide(description: "Das Datum der Erstellung des Dokuments, falls erkennbar, sonst null")
    var date: String?

    @Guide(description: "Name des Absenders oder des absendenden Unternehmens, kurz und prägnant. Steht meist oben im Dokument.")
    var sender: String?

    @Guide(description: "Betreff oder Titel des Dokuments, max. 60 Zeichen, sinnerhaltend kürzen")
    var subject: String?

    @Guide(description: "Themenbereich des Dokuments, exakt einer der vorgegebenen Werte oder null")
    var topic: String?

    @Guide(description: "Konfidenz für das Datum, Wert zwischen 0.0 und 1.0")
    var dateConfidence: Double

    @Guide(description: "Konfidenz für den Absender, Wert zwischen 0.0 und 1.0")
    var senderConfidence: Double

    @Guide(description: "Konfidenz für den Betreff, Wert zwischen 0.0 und 1.0")
    var subjectConfidence: Double

    @Guide(description: "Konfidenz für den Themenbereich, Wert zwischen 0.0 und 1.0")
    var topicConfidence: Double
}

// MARK: - Extraktor

struct MetadataExtractor {

    private let config: Config

    init(config: Config) {
        self.config = config
    }

    // MARK: - Hauptmethode

    func extract(from ocrResult: OCRResult, inboxPath: URL?, sourceURL: URL) async throws -> DocumentMetadata {

        // Text auf sinnvolle Länge kürzen (Modell hat Kontextlimit)
        let trimmedText = trimText(ocrResult.text, maxChars: 3000)

        // Empfänger via String-Matching (kein LLM nötig, deterministisch)
        let matchedMembers = config.matchingMembers(in: ocrResult.text)

        // LLM-Extraktion
        let extracted = try await runExtraction(text: trimmedText)

        // Datum parsen
        let dateComponents = parseDate(extracted.date) ?? fileDateComponents(of: sourceURL)

        // Topic validieren (nur Werte aus Config erlaubt)
        let validatedTopic = validateTopic(extracted.topic)

        // Konfidenz zusammenbauen
        let confidence = MetadataConfidence(
            date:    extracted.dateConfidence,
            sender:  extracted.senderConfidence,
            subject: extracted.subjectConfidence,
            topic:   extracted.topicConfidence,
            overall: [
                extracted.dateConfidence,
                extracted.senderConfidence,
                extracted.subjectConfidence,
                extracted.topicConfidence
            ].reduce(0, +) / 4.0
        )

        return DocumentMetadata(
            date:       dateComponents,
            sender:     extracted.sender,
            subject:    extracted.subject,
            topic:      validatedTopic,
            recipients: matchedMembers.map(\.shortName),
            confidence: confidence
        )
    }

    private func fileDateComponents(of url: URL) -> DateComponents? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let date = attributes?[.creationDate] as? Date else { return nil }
        return Calendar.current.dateComponents([.year, .month, .day], from: date)
    }
  
    // MARK: - Foundation Models Aufruf

    private func runExtraction(text: String) async throws -> ExtractedMetadata {
        let model = SystemLanguageModel.default

        // Verfügbarkeit prüfen
        guard case .available = model.availability else {
            throw MetadataError.modelUnavailable
        }

        let session = LanguageModelSession()

        let topicList = config.topics.joined(separator: ", ")

        let prompt = """
        Analysiere den folgenden deutschen Dokumenttext und extrahiere die Metadaten.
        
        Erlaubte Themenbereiche: \(topicList)
        
        Antworte ausschließlich mit dem strukturierten Output, keine Erklärungen.
        
        Dokumenttext:
        ---
        \(text)
        ---
        """

        let response = try await session.respond(
            to: prompt,
            generating: ExtractedMetadata.self
        )

        return response.content
    }

    // MARK: - Hilfsmethoden

    /// Kürzt den Text auf maxChars, bevorzugt die erste Seite
    /// (Absender, Datum, Betreff stehen meist oben)
    private func trimText(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        return String(text.prefix(maxChars)) + "\n[Text gekürzt...]"
    }

    /// Parst YYYY-MM-DD in DateComponents
    private func parseDate(_ dateString: String?) -> DateComponents? {
        guard let dateString else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "de_DE")

        guard let date = formatter.date(from: dateString) else { return nil }

        return Calendar.current.dateComponents([.year, .month, .day], from: date)
    }

    /// Stellt sicher, dass das Topic aus der Config-Liste stammt
    private func validateTopic(_ topic: String?) -> String? {
        guard let topic else { return nil }
        return config.topics.first {
            $0.lowercased() == topic.lowercased()
        }
    }
}

// MARK: - Fehler

enum MetadataError: LocalizedError {
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "Apple Foundation Models nicht verfügbar (Gerät unterstützt Apple Intelligence nicht)"
        }
    }
}
