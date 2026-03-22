//
//  AuditEntry.swift
//  
//
//  Created by Matthias Wronka on 22.03.26.
//


import Foundation

struct AuditEntry: Codable {
    let timestamp: String
    let filename: String
    let decision: String
    let reason: String
    let confidence: Double
    let extractedMetadata: AuditMetadata?
}

struct AuditMetadata: Codable {
    let date: String?
    let sender: String?
    let subject: String?
    let topic: String?
    let recipients: [String]
}

struct AuditLog {

    static var logFileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/docsorter/audit.log")
    }

    static func write(
        file: String,
        decision: String,
        reason: String,
        confidence: Double,
        metadata: DocumentMetadata? = nil
    ) {
        let entry = AuditEntry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            filename: file,
            decision: decision,
            reason: reason,
            confidence: confidence,
            extractedMetadata: metadata.map {
                AuditMetadata(
                    date:       formatDate($0.date),
                    sender:     $0.sender,
                    subject:    $0.subject,
                    topic:      $0.topic,
                    recipients: $0.recipients
                )
            }
        )

        guard let data = try? JSONEncoder().encode(entry),
              var line = String(data: data, encoding: .utf8)
        else { return }

        line += "\n"

        // Anhängen an Log-Datei
        let url = logFileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                try? handle.close()
            }
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func formatDate(_ components: DateComponents?) -> String? {
        guard let c = components,
              let year = c.year, let month = c.month, let day = c.day
        else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
