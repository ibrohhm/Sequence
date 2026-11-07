import SwiftUI
import StudioCore

/// The vault list shared by every window and the Settings window.
@MainActor final class VaultStore: ObservableObject {
    static let shared = VaultStore()

    @Published private(set) var vaults: [Vault]
    @Published var activePath: String?

    private init() { vaults = VaultList.load(from: VaultList.defaultFile()).vaults }

    /// Reloads the list from disk, applies `change`, and saves it.
    func update(_ change: (inout VaultList) throws -> Void) throws {
        var list = VaultList.load(from: VaultList.defaultFile())
        try change(&list)
        try list.save(to: VaultList.defaultFile())
        vaults = list.vaults
    }
}
