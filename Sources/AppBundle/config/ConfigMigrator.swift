import OrderedCollections

struct ConfigMigrationCandidate: Equatable {
    let text: String
    let fromVersion: Int
    let toVersion: Int
    let semanticChanges: [String]
    let persistentWorkspaces: [String]
}

enum ConfigMigrationError: Error, Equatable {
    case unsupportedPath(from: Int, to: Int)
    case invalidSource([String])
    case invalidCandidate([String])
    case semanticMismatch(String)
}

@MainActor
enum ConfigMigrator {
    static func migrate(text: String, from: Int, to: Int) -> Result<ConfigMigrationCandidate, ConfigMigrationError> {
        guard from == 1, to == 2 else {
            return .failure(.unsupportedPath(from: from, to: to))
        }

        let document = TomlBlockDocument(text)
        let source = parseConfig(text)
        guard source.errors.isEmpty else { return .failure(.invalidSource(source.errors)) }
        guard source.config.configVersion == from else {
            return .failure(.semanticMismatch("Source config-version is \(source.config.configVersion), expected \(from)"))
        }

        let keyMappingPreamble = document.text(forTablesMatching: { $0 == "key-mapping" || $0.hasPrefix("key-mapping.") })
        var persistentWorkspaces = OrderedSet<String>()

        for entry in document.keyValueTexts(inTableMatching: { $0.hasPrefix("mode.") && $0.hasSuffix(".binding") }) {
            var oneBinding = keyMappingPreamble
            if entry.table != "mode.main.binding" { oneBinding += "[mode.main.binding]\n" }
            oneBinding += "[\(entry.table)]\n\(entry.text)"
            let parsed = parseConfig(oneBinding)
            guard parsed.errors.isEmpty else { return .failure(.invalidSource(parsed.errors)) }

            let bindings = parsed.config.modes.values.flatMap { $0.bindings.values }
            guard bindings.count == 1 else {
                return .failure(.semanticMismatch("Expected one binding while parsing \(entry.table)"))
            }
            for command in bindings[0].commands {
                if let workspace = (command as? WorkspaceCommand)?.args.target.val.workspaceNameOrNil()?.raw {
                    persistentWorkspaces.append(workspace)
                }
                if let workspace = (command as? MoveNodeToWorkspaceCommand)?.args.target.val.workspaceNameOrNil()?.raw {
                    persistentWorkspaces.append(workspace)
                }
            }
        }

        for entry in document.keyValueTexts(inTableMatching: { $0 == "workspace-to-monitor-force-assignment" }) {
            let parsed = parseConfig("[\(entry.table)]\n\(entry.text)")
            guard parsed.errors.isEmpty else { return .failure(.invalidSource(parsed.errors)) }
            guard let workspace = parsed.config.workspaceToMonitorForceAssignment.keys.first else {
                return .failure(.semanticMismatch("Expected one workspace assignment"))
            }
            persistentWorkspaces.append(workspace)
        }

        guard Set(persistentWorkspaces) == Set(source.config.persistentWorkspaces) else {
            return .failure(.semanticMismatch("Source and migrated persistent workspace membership differ"))
        }

        var candidateDocument = document
        candidateDocument.set(key: "config-version", tomlValue: TomlValue.of(2))
        candidateDocument.set(
            key: "persistent-workspaces",
            tomlValue: TomlValue.array(persistentWorkspaces.map(TomlValue.of)),
        )
        let candidateText = candidateDocument.render()
        let candidate = parseConfig(candidateText)
        guard candidate.errors.isEmpty else { return .failure(.invalidCandidate(candidate.errors)) }

        var sourceDraft = ConfigTomlWriter.draft(
            from: source.config,
            rawExec: SettingsModel.rawExecConfig(from: text),
            document: document,
        )
        var candidateDraft = ConfigTomlWriter.draft(
            from: candidate.config,
            rawExec: SettingsModel.rawExecConfig(from: candidateText),
            document: candidateDocument,
        )
        sourceDraft.configVersion = candidateDraft.configVersion
        sourceDraft.persistentWorkspaces = OrderedSet(sourceDraft.persistentWorkspaces.sorted())
        candidateDraft.persistentWorkspaces = OrderedSet(candidateDraft.persistentWorkspaces.sorted())
        guard sourceDraft == candidateDraft else {
            return .failure(.semanticMismatch("Migrated config does not preserve the source semantics"))
        }

        return .success(
            ConfigMigrationCandidate(
                text: candidateText,
                fromVersion: from,
                toVersion: to,
                semanticChanges: [],
                persistentWorkspaces: Array(persistentWorkspaces),
            ),
        )
    }
}
