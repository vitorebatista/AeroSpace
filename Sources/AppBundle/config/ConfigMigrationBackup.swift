import Foundation

struct ConfigMigrationBackup: Equatable {
    let url: URL

    static func create(
        forResolvedTarget target: URL,
        fromVersion: Int,
        now: Date = Date(),
        fileManager: FileManager = .default,
    ) throws -> ConfigMigrationBackup {
        let target = target.standardizedFileURL
        let source = try Data(contentsOf: target)
        let attributes = try fileManager.attributesOfItem(atPath: target.path)
        let permissions = attributes[.posixPermissions]
        let baseName = "\(target.lastPathComponent).backup-v\(fromVersion)-\(timestamp(now))"

        var suffix = 1
        while true {
            let name = suffix == 1 ? baseName : "\(baseName)-\(suffix)"
            let destination = target.deletingLastPathComponent().appending(path: name)
            do {
                try source.write(to: destination, options: .withoutOverwriting)
            } catch {
                if isFileExistsError(error) {
                    suffix += 1
                    continue
                }
                throw error
            }

            do {
                if let permissions {
                    try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: destination.path)
                }
                return ConfigMigrationBackup(url: destination.absoluteURL)
            } catch {
                try? fileManager.removeItem(at: destination)
                throw error
            }
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func isFileExistsError(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileWriteFileExists.rawValue
    }
}
