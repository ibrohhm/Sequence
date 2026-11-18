import Foundation

/// Files from App/Resources: the app bundle when built, the source folder when run from source.
enum AppResources {
    static func url(_ file: String) -> URL {
        let name = (file as NSString).deletingPathExtension, ext = (file as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext.isEmpty ? nil : ext)
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/\(file)")
    }

    static func text(_ file: String) -> String {
        (try? String(contentsOf: url(file), encoding: .utf8)) ?? ""
    }
}
