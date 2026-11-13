import Foundation

/// Uses the editable visible label for its export directory while keeping
/// source filenames and relative subdirectories unchanged.
public enum PriorityTagExportFolders {
    public static func paths(
        under root: URL,
        definitions: [PriorityTagDefinition]
    ) -> [PriorityTag: String] {
        Dictionary(uniqueKeysWithValues: PriorityTagCatalog.normalized(definitions).map { definition in
            (definition.tag, root.appendingPathComponent(definition.name, isDirectory: true).path)
        })
    }
}
