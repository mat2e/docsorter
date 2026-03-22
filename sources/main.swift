//
//  DocSorter.swift
//  
//
//  Created by Matthias Wronka on 22.03.26.
//


import Foundation

// MARK: - Entry Point
struct DocSorter {
    static func main() async throws {
        let args = CommandLine.arguments
        
        guard args.count > 1 else {
            printUsage()
            exit(1)
        }
        
        // Konfiguration laden
        let config = try Config.load()
        
        // Dateien verarbeiten
        let inputPaths = args.dropFirst().map { URL(fileURLWithPath: $0) }
        
        for inputURL in inputPaths {
            do {
                print("Verarbeite: \(inputURL.lastPathComponent)")
                try await processDocument(at: inputURL, config: config)
            } catch {
                print("Fehler bei \(inputURL.lastPathComponent): \(error)")
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
        // 1. OCR
        // 2. Metadaten extrahieren
        // 3. Tags setzen
        // 4. Ablegen
        // → wird Schritt für Schritt befüllt
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

// Swift 6 Concurrency: Top-level async entry point
try await DocSorter.main()