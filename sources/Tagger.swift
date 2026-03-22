//
//  TagSet.swift
//  
//
//  Created by Matthias Wronka on 22.03.26.
//


import Foundation
import PDFKit

struct TagSet {
    let recipients: [String]    // shortNames der Familienmitglieder
    let year: String?           // "2024"
    let topic: String?          // "Finanzen"
    let sender: String?         // "AOK Bayern"
    

    /// Alle Tags als flache Liste, dedupliziert und bereinigt
    var all: [String] {
        var tags: [String] = []
        tags.append(contentsOf: recipients)
        if let year    { tags.append(year) }
        if let topic   { tags.append(topic) }
        if let sender  { tags.append(sender) }
        
        // Leerzeichen trimmen, Duplikate entfernen, Leerstrings raus
        return Array(
            Set(tags.map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty })
        ).sorted()
    }

    /// Aus DocumentMetadata erzeugen
    static func from(_ metadata: DocumentMetadata) -> TagSet {
        let year = metadata.date?.year.map { String($0) }
        return TagSet(
            recipients: metadata.recipients,
            year:       year,
            topic:      metadata.topic,
            sender:     metadata.sender,        
        )
    }

    /// Betreff auf max. 40 Zeichen kürzen (für Tags sinnvoll)
    private static func shortenSubject(_ subject: String) -> String {
        guard subject.count > 40 else { return subject }
        return String(subject.prefix(37)) + "..."
    }
}

// MARK: - Tagger

struct Tagger {

    // MARK: - Hauptmethode

    static func apply(tags: TagSet, to pdfURL: URL) throws {
        try setFinderTags(tags.all, on: pdfURL)
        try setPDFKeywords(tags.all, on: pdfURL)
        print("  → Tags gesetzt: \(tags.all.joined(separator: ", "))")
    }

    // MARK: - Finder-Tags

    /// Setzt macOS Finder-Tags (erscheinen in Spotlight und Finder-Sidebar)
    private static func setFinderTags(_ tags: [String], on url: URL) throws {
        try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
    }

    // MARK: - PDF Keywords

    /// Schreibt Tags als Keywords in die PDF-Dokumenteigenschaften
    private static func setPDFKeywords(_ tags: [String], on url: URL) throws {
        guard let document = PDFDocument(url: url) else {
            throw TaggerError.cannotOpenPDF(url.path)
        }

        // Bestehende Attribute lesen und Keywords ergänzen
        var attributes = document.documentAttributes ?? [:]
        attributes[PDFDocumentAttribute.keywordsAttribute] = tags

        document.documentAttributes = attributes

        // Zurückschreiben
        guard document.write(to: url) else {
            throw TaggerError.cannotWritePDF(url.path)
        }
    }
}

// MARK: - Fehler

enum TaggerError: LocalizedError {
    case cannotOpenPDF(String)
    case cannotWritePDF(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpenPDF(let path): return "PDF kann nicht geöffnet werden: \(path)"
        case .cannotWritePDF(let path): return "PDF kann nicht geschrieben werden: \(path)"
        }
    }
}
