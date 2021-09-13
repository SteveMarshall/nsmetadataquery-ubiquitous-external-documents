import Combine
import SwiftUI
import UniformTypeIdentifiers

@main
struct NSMetadataQueryUbiquitousExternalDocumentsTestApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var importing: Importing? = nil
    @State private var importedItems = [URL]()

    @State private var query = NSMetadataQuery()
    @State private var fileMonitor: AnyCancellable? = nil
    @State private var foundItems = [NSMetadataItem]()

    @State private var rootURL: URL? = nil

    var body: some Scene {
        WindowGroup {
            NavigationView {
                List {
                    Section("Imported items") {
                        ForEach(importedItems, id: \.absoluteString) { imported in
                            Text(imported.lastPathComponent)
                        }
                    }

                    Section("Found items") {
                        ForEach(foundItems, id: \.fileSystemName) { found in
                            Text(found.fileSystemName)
                        }
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button(action: { importing = .file }, label: {
                            Label("Import file", systemImage: "arrow.down.doc")
                        })
                        Button(action: { importing = .folder }, label: {
                            Label("Import folder", systemImage: "square.and.arrow.down")
                        })
                    }
                }
                .fileImporter(
                    isPresented: Binding(
                        get: { importing != nil },
                        set: { _ in importing = nil }
                    ),
                    allowedContentTypes: importing?.allowedContentTypes ?? [],
                    allowsMultipleSelection: true,
                    onCompletion: importFiles
                )
                .navigationTitle("MetadataQuery Test")
                .onChange(of: scenePhase) { newPhase in
                    guard newPhase == .active else { return }

                    configureUbiquityAccess(
                        to: "iCloud.com.stevemarshall.AnnotateML",
                        then: findAccessibleFiles
                    )
                }
            }
        }
    }
}

extension NSMetadataQueryUbiquitousExternalDocumentsTestApp {
    func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            return
        }
        importedItems.append(
            contentsOf: urls
        )
    }
}

extension NSMetadataQueryUbiquitousExternalDocumentsTestApp {
    func configureUbiquityAccess(
        to container: String? = nil,
        then access: (() -> Void)?
    ) {
        DispatchQueue.global().async {
            guard let _ = FileManager.default.url(forUbiquityContainerIdentifier: container) else {
                print("⛔️ Failed to configure iCloud container URL for: \(container ?? "nil")\n"
                        + "Make sure your iCloud is available and run again.")
                return
            }

            print("Successfully configured iCloud container")
            access.map { DispatchQueue.main.async(execute: $0) }
        }
    }

    func findAccessibleFiles() {
        query.stop()
        fileMonitor?.cancel()

        fileMonitor = Publishers.MergeMany(
            [
                .NSMetadataQueryDidFinishGathering,
                .NSMetadataQueryDidUpdate
            ].map { NotificationCenter.default.publisher(for: $0) }
        )
            .receive(on: DispatchQueue.main)
            .sink { notification in
                query.disableUpdates()
                defer { query.enableUpdates() }

                foundItems = query.results as! [NSMetadataItem]
                print("Query posted \(notification.name.rawValue) with results: \(query.results)")
            }

        query.searchScopes = [
            NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope,
            rootURL as Any
        ]
        query.predicate = NSPredicate(
            format: "%K LIKE %@",
            argumentArray: [NSMetadataItemFSNameKey, "*"]
        )
        query.sortDescriptors = [
            NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)
        ]

        if query.start() {
            print("Query started")
        } else {
            print("Query didn't start for some reason")
        }
    }
}

extension NSMetadataQueryUbiquitousExternalDocumentsTestApp {
    private enum Importing {
        case folder
        case file

        var allowedContentTypes: [UTType] {
            switch self {
            case .folder: return [.folder]
            case .file: return [.content]
            }
        }
    }
}

extension NSMetadataItem {
    var fileSystemName: String {
        guard let fileSystemName = value(
            forAttribute: NSMetadataItemFSNameKey
        ) as? String else { return "" }

        return fileSystemName
    }
}
