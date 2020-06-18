//
//  ContentView.swift
//  BearExport
//
//  Created by Johnny Sheeley on 6/13/20.
//  Copyright © 2020 Johnny Sheeley. All rights reserved.
//

import SwiftUI
import class SQLite.Connection
import class SQLite.Statement

let bearPath = ("~/Library/Group Containers/9K33E3U3T4.net.shinyfrog.bear/" as NSString).expandingTildeInPath
let bearDBPath = "Application Data/database.sqlite"
let bearFilesPath = "Local Files"
let fm = FileManager.default

struct ContentView: View {
    @State var sourceURL: URL?
    @State var destinationURL: URL?
    @State private var start: Date?
    @State private var end: Date?
    @State private var totalNotes = 0
    @State private var processedNotes = 0
    @State private var filesCopied = 0
    @State private var exporting = false
    @State private var includeTrashed = false
    @State private var errors : [String] = []
}

// MARK: Main View
extension ContentView {
    var body: some View {
        Form {
            VStack {
                Text("Bear Export").font(.largeTitle)
                Spacer()

                if !exporting {
                    sourceForm

                    destinationForm

                    Spacer()

                    exportView
                } else if end != nil {
                    Text("Processed \(totalNotes) notes in \(humanDuration(duration: end!.timeIntervalSince(start!)))")
                    if filesCopied > 0 {
                        Text("\(filesCopied) files copied")
                    }
                } else {
                    Spacer()
                    ProgressBar(currentValue: processedNotes, total: totalNotes).frame(maxHeight: 40)
                }

                if !errors.isEmpty {
                    Spacer()
                    List {
                        ForEach(errors, id: \.self) { err in
                            Text(err).foregroundColor(Color.red).truncationMode(.head)
                        }
                    }
                }
            }
        }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Source Form
extension ContentView {
    var sourceForm: some View {
        VStack {
            if sourceURL == nil {
                Button(action: {
                    let directory = URL(fileURLWithPath: bearPath)
                    let panel = NSOpenPanel()
                    panel.allowedFileTypes = ["sqlite"]
                    panel.directoryURL = directory
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        let result = panel.runModal()
                        if result == .OK, let url = panel.url {
                            let dbPath = url.appendingPathComponent(bearDBPath)
                            if fm.fileExists(atPath: dbPath.path) {
                                self.sourceURL = url
                            }
                        }
                    }
                }) {
                    Text("Open Bear Directory")
                }
                Text("Select Bear's data directory to grant permission to read").font(.caption)
            } else {
                Text("Bear directory readable").font(.caption)
            }
        }
    }
}

// MARK: Destination Form
extension ContentView {
    var destinationForm: some View {
        Section {
            Button(action: {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.canCreateDirectories = true
                panel.directoryURL = fm.homeDirectoryForCurrentUser

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let result = panel.runModal()
                    if result == .OK {
                        self.destinationURL = panel.url
                    }
                }
            }) {
                Text("Select output directory")
            }

            if destinationURL != nil {
                Text(destinationURL!.absoluteString)
            }
        }
    }
}

// MARK: Export view
extension ContentView {
    var exportView: some View {
        return VStack {
            Toggle(isOn: $includeTrashed) {
                Text("Include trashed notes")
            }

            Button(action: {
                self.exportNotes()
            }) {
                Text("Export!")
            }.disabled(sourceURL == nil || destinationURL == nil)
        }
    }
}


// MARK: Export logic
let fileRegex = try! NSRegularExpression(pattern: "\\[(image|file):(.*)\\]", options: [])
extension ContentView {
    func exportNotes() {
        guard let sourceURL = sourceURL else { return }
        let databasePath = sourceURL.appendingPathComponent(bearDBPath)

        exporting = true
        start = Date()

        DispatchQueue.global(qos: .background).async {
            let shouldStopAccessing = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let db = try Connection(databasePath.absoluteString, readonly: true)
                try self.processNotes(db: db, withTrashed: self.includeTrashed)
            } catch {
                self.errors.append(error.localizedDescription)
            }
        }
    }


    func processNotes(db: Connection, withTrashed: Bool) throws {
        guard let sourceURL = sourceURL, let destDir = destinationURL else { return }
        let baseDir = sourceURL.appendingPathComponent("Application Data").appendingPathComponent("Local Files")

        let whereClause = withTrashed ? "" : " WHERE ZTRASHED=0"
        let countQuery = "SELECT COUNT(*) FROM ZSFNOTE\(whereClause);"
        if let total = try db.scalar(countQuery) as? Int64 {
            DispatchQueue.main.async {
                self.totalNotes = Int(total)
            }
        }

        let encoder = JSONEncoder()
        let query = "SELECT ZUNIQUEIDENTIFIER, ZTEXT, ZHASIMAGES, ZHASFILES, ZTRASHED, ZCREATIONDATE, ZMODIFICATIONDATE, ZPINNED FROM ZSFNOTE\(whereClause);"
        var toCopy = Dictionary<URL,URL>()
        for row in try db.prepare(query) {
            let note = BearNote(row)
            if note.hasImages || note.hasFiles {
                let text = note.text
                let range = NSRange(text.startIndex..<text.endIndex, in: text)

                fileRegex.enumerateMatches(in: text, options: [], range: range, using: { (match, _, _) in
                    guard let match = match, match.numberOfRanges == 3,
                        let kindRange = Range(match.range(at: 1), in: text),
                        let nameRange = Range(match.range(at: 2), in: text) else { return }

                    let kind = text[kindRange]
                    let name = String(text[nameRange])

                    let dir = (kind == "file") ? "Note Files" : "Note Images"
                    let sourceFile = baseDir.appendingPathComponent(dir).appendingPathComponent(name)
                    let destinationFile = destDir.appendingPathComponent(name)
                    toCopy[sourceFile] = destinationFile
                })
            }

            let filePath = destDir.appendingPathComponent("\(note.id).json")
            let jsonData = try encoder.encode(note)
            try jsonData.write(to: filePath)

            DispatchQueue.main.async {
                self.processedNotes += 1
            }
        }

        for (sourceFile, destinationFile) in toCopy {
            if fm.fileExists(atPath: sourceFile.path) {
                try? fm.createDirectory(at: destinationFile, withIntermediateDirectories: true, attributes: [:])
                try? fm.copyItem(at: sourceFile, to: destinationFile)
                DispatchQueue.main.async {
                    self.filesCopied += 1
                }
            } else {
                DispatchQueue.main.async {
                    self.errors.append("\(sourceFile.path.replacingOccurrences(of: baseDir.path, with: "")) could not be found")
                }
            }
        }

        DispatchQueue.main.async {
            self.end = Date()
        }
    }
}

// MARK: Bear notes
struct BearNote: Codable {
    let id: String
    let text: String
    let hasImages: Bool
    let hasFiles: Bool
    let trashed: Bool
    let creationDate: Date
    let modificationDate: Date
    let pinned: Bool

    init(_ row: Statement.Element) {
        id = row[0] as! String
        text = row[1] as! String
        hasImages = (row[2] as! Int64) == 1
        hasFiles = (row[3] as! Int64) == 1
        trashed = (row[4] as! Int64) == 1
        let c = (row[5] as! NSNumber).doubleValue
        if let cre = TimeInterval(exactly: c) {
            creationDate = Date(timeIntervalSinceReferenceDate: cre)
        } else {
            creationDate = Date()
        }
        modificationDate = Date(timeIntervalSinceReferenceDate: TimeInterval(truncating: row[6] as! NSNumber))
        pinned = (row[7] as! Int64) == 1
    }
}

func humanDuration(duration: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .positional
    formatter.allowedUnits = [.minute, .second]
    formatter.zeroFormattingBehavior = [.pad]
    return formatter.string(from: duration) ?? "\(duration)"
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
