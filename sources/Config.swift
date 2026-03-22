//
//  FamilyMember.swift
//  
//
//  Created by Matthias Wronka on 22.03.26.
//


import Foundation

struct DebugConfig: Codable {
    let keepOriginals: Bool
}

struct FamilyMember: Codable {
    let fullName: String
    let shortName: String
    let aliases: [String]?

    /// Alle Suchbegriffe – aliases wenn angegeben, sonst fullName
    var searchTerms: [String] {
        aliases ?? [fullName]
    }
}

struct OutputRule: Codable {
    let topic: String        // "*" = Fallback
    let pathTemplate: String
}

struct ConfidenceConfig: Codable {
    let auditThreshold: Double
}

struct Config: Codable {
    let familyMembers: [FamilyMember]
    let topics: [String]
    let inboxFolderToTopic: [String: String?]
    let outputRules: [OutputRule]
    let baseOutputDir: String
    let confidence: ConfidenceConfig
    let debug: DebugConfig?
  
    var shouldKeepOriginals: Bool {
        debug?.keepOriginals ?? false
    }

    // MARK: - Laden

    static func load() throws -> Config {
        let configURL = Self.configFileURL
        
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw ConfigError.fileNotFound(configURL.path)
        }
        
        let data = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        return try decoder.decode(Config.self, from: data)
    }

    static var configFileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/docsorter/config.json")
    }

    // MARK: - Hilfsmethoden

    /// Findet alle Familienmitglieder, deren aliases im Text vorkommen
    func matchingMembers(in text: String) -> [FamilyMember] {
        let lowercasedText = text.lowercased()
        return familyMembers.filter { member in
            member.searchTerms.contains { term in
                lowercasedText.contains(term.lowercased())
            }
        }
    }

    /// Liefert die passende OutputRule für ein Topic
    func outputRule(for topic: String) -> OutputRule? {
        outputRules.first { $0.topic == topic }
        ?? outputRules.first { $0.topic == "*" }
    }

    /// Liefert das Topic für einen Eingangsordner (nil = unbekannt)
    func topic(forInboxPath path: String) -> String?? {
        inboxFolderToTopic[path]
    }
  
  // MARK: - Pfad-Hilfsmethoden

  // In Config:
  var expandedBaseOutputDir: String {
      baseOutputDir.expandingTildeInPath
  }

  func expandedInboxFolderToTopic() -> [String: String?] {
      Dictionary(uniqueKeysWithValues:
          inboxFolderToTopic.map { key, value in
              (key.expandingTildeInPath, value)
          }
      )
  }

}

extension String {
    var expandingTildeInPath: String {
        (self as NSString).expandingTildeInPath
    }
}

// MARK: - Fehler

enum ConfigError: LocalizedError {
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Konfigurationsdatei nicht gefunden: \(path)"
        }
    }
}



