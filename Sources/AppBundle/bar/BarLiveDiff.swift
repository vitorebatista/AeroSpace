/// Turns the difference between two `BarDraft`s into the sketchybar commands that move a
/// running bar from one to the other.
///
/// Pure, for the same reason `BarConfigGenerator` is: no I/O, no process, no environment.
/// This is the component whose bugs would silently desync the bar on screen from the config
/// on disk, so it has to be the one that is trivial to test.
///
/// Both sides go through `BarConfigGenerator.plan`, so a live-edited bar and a
/// saved-then-reloaded bar are described by the same resolution of the same draft. Items the
/// generator skips — a privileged item, an unknown id, a `custom` with no script — are
/// skipped here too, because they are not entities in either plan.
enum BarLiveDiff {
    /// Argument vectors, in the order they have to be applied. Each is one sketchybar
    /// command: `["--set", "aerospace.clock", "update_freq=1"]`.
    static func commands(from previous: BarDraft, to next: BarDraft, helpers: BarHelperPaths) -> [[String]] {
        commands(
            from: BarConfigGenerator.plan(previous, helpers: helpers),
            to: BarConfigGenerator.plan(next, helpers: helpers),
        )
    }

    static func commands(from before: BarPlan, to after: BarPlan) -> [[String]] {
        guard before != after else { return [] }
        var commands: [[String]] = []

        let barChanges = changed(from: before.bar, to: after.bar)
        if !barChanges.isEmpty { commands.append(["--bar"] + barChanges) }

        let defaultChanges = changed(from: before.defaults, to: after.defaults)
        if !defaultChanges.isEmpty { commands.append(["--default"] + defaultChanges) }
        // sketchybar applies `--default` to items added *after* it, so a palette change
        // reaches what is already on screen only by rebuilding every entity. It is the one
        // edit that cannot be narrowed, and it is rare — a colour well, not a drag.
        let rebuildEverything = !defaultChanges.isEmpty

        let beforeEntities = uniqueByName(before.entities)
        let afterEntities = uniqueByName(after.entities)
        let beforeByName = Dictionary(beforeEntities.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let afterNames = Set(afterEntities.map(\.name))

        var rebuilt = Set(afterEntities.filter { entity in
            guard let old = beforeByName[entity.name] else { return false }
            return rebuildEverything || needsRebuild(from: old, to: entity)
        }.map(\.name))
        // A bracket holds its members by reference, so removing one drops it out of the
        // bracket for good. A bracket therefore outlives none of its rebuilt members.
        let recreated = Set(afterEntities
            .filter { !$0.isBracket && (beforeByName[$0.name] == nil || rebuilt.contains($0.name)) }
            .map(\.name))
        for entity in afterEntities where entity.isBracket && beforeByName[entity.name] != nil {
            guard case .bracket(let members) = entity.kind else { continue }
            if members.contains(where: recreated.contains) { rebuilt.insert(entity.name) }
        }
        let rebuiltNames = rebuilt
        func isNew(_ entity: BarPlanEntity) -> Bool {
            beforeByName[entity.name] == nil || rebuiltNames.contains(entity.name)
        }

        // Brackets go first: one that is about to lose a member must not outlive it, and a
        // bracket removed before its members is one fewer redraw with a stale span.
        let removed = (beforeEntities.filter(\.isBracket) + beforeEntities.filter { !$0.isBracket })
            .filter { !afterNames.contains($0.name) || rebuiltNames.contains($0.name) }
        for entity in removed { commands.append(["--remove", entity.name]) }

        for entity in afterEntities where !entity.isBracket && isNew(entity) {
            commands.append(contentsOf: creation(of: entity))
        }
        for entity in afterEntities where !entity.isBracket && !isNew(entity) {
            let changes = changed(from: beforeByName[entity.name]?.properties ?? [], to: entity.properties)
            if !changes.isEmpty { commands.append(["--set", entity.name] + changes) }
        }

        commands.append(contentsOf: reorders(
            from: beforeEntities,
            to: afterEntities,
            survives: { !isNew($0) && afterNames.contains($0.name) },
        ))

        // Brackets last: a bracket draws around whatever span its members occupy, so it is
        // added once the item order has settled.
        for entity in afterEntities where entity.isBracket {
            if isNew(entity) {
                commands.append(contentsOf: creation(of: entity))
            } else {
                let changes = changed(from: beforeByName[entity.name]?.properties ?? [], to: entity.properties)
                if !changes.isEmpty { commands.append(["--set", entity.name] + changes) }
            }
        }
        return commands
    }

    // MARK: -

    private static func creation(of entity: BarPlanEntity) -> [[String]] {
        var commands = [entity.addArguments]
        if !entity.properties.isEmpty {
            commands.append(["--set", entity.name] + entity.properties.map(\.text))
        }
        if !entity.events.isEmpty { commands.append(["--subscribe", entity.name] + entity.events) }
        return commands
    }

    /// Whether an entity has to be removed and re-added rather than `--set` in place.
    ///
    /// Each of these is something sketchybar has no command to change: the component an
    /// `--add` created, the position it was added to, the events it is subscribed to (there
    /// is no unsubscribe), and a property the next plan no longer names — dropping a key
    /// means going back to the inherited default, and only a fresh `--add` does that.
    private static func needsRebuild(from old: BarPlanEntity, to new: BarPlanEntity) -> Bool {
        old.kind != new.kind
            || old.cluster != new.cluster
            || old.events != new.events
            || !droppedKeys(from: old.properties, to: new.properties).isEmpty
    }

    /// A `--reorder` per cluster, and only where the order would otherwise be wrong.
    ///
    /// `--add` appends to the end of its cluster, so the projected order after the removals
    /// and additions above is the survivors in their old relative order followed by the new
    /// entities in the order they were added. Where that already matches, nothing is emitted.
    private static func reorders(
        from before: [BarPlanEntity],
        to after: [BarPlanEntity],
        survives: (BarPlanEntity) -> Bool,
    ) -> [[String]] {
        var commands: [[String]] = []
        for cluster in BarCluster.allCases {
            let target = after.filter { !$0.isBracket && $0.cluster == cluster }
            guard target.count > 1 else { continue }
            let surviving = Set(target.filter(survives).map(\.name))
            var projected = before
                .filter { !$0.isBracket && $0.cluster == cluster && surviving.contains($0.name) }
                .map(\.name)
            projected += target.map(\.name).filter { !surviving.contains($0) }
            let names = target.map(\.name)
            if projected != names { commands.append(["--reorder"] + names) }
        }
        return commands
    }

    /// The arguments of `after` whose value `before` did not already carry.
    private static func changed(from before: [BarArgument], to after: [BarArgument]) -> [String] {
        let old = keyed(before)
        return after.filter { old[$0.key] != $0.value }.map(\.text)
    }

    private static func droppedKeys(from before: [BarArgument], to after: [BarArgument]) -> Set<String> {
        Set(before.map(\.key)).subtracting(after.map(\.key))
    }

    private static func keyed(_ arguments: [BarArgument]) -> [String: String] {
        Dictionary(arguments.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
    }

    /// Two runs of one catalog group in one cluster produce the same bracket name. sketchybar
    /// would keep whichever was added first, so the diff works from the same first-wins view
    /// instead of emitting a second `--add` for a name that already exists.
    private static func uniqueByName(_ entities: [BarPlanEntity]) -> [BarPlanEntity] {
        var seen: Set<String> = []
        return entities.filter { seen.insert($0.name).inserted }
    }
}
