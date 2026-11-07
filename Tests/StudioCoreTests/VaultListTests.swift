import Testing
import Foundation
@testable import StudioCore

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vl \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.resolvingSymlinksInPath()
}

@Suite struct VaultListTests {
    @Test func addingAFolderNamesTheVaultAfterIt() throws {
        var list = VaultList()
        let vault = list.add(folder: URL(fileURLWithPath: "/tmp/notes"))
        #expect(vault.name == "notes")
        #expect(list.vaults == [vault])
    }

    @Test func addingTheSameFolderTwiceKeepsOneVault() {
        var list = VaultList()
        let first = list.add(folder: URL(fileURLWithPath: "/tmp/notes"))
        let second = list.add(folder: URL(fileURLWithPath: "/tmp/notes/"))
        #expect(first == second)
        #expect(list.vaults.count == 1)
    }

    @Test func creatingAVaultMakesItsFolderInTheDefaultPlace() throws {
        let base = try tempDir()
        var list = VaultList()
        let vault = try list.create(named: " Work ", in: base)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("Work").path, isDirectory: &isDir) && isDir.boolValue)
        #expect(vault.name == "Work")
        #expect(list.vaults.contains(vault))
    }

    @Test func creatingCreatesMissingDefaultPlace() throws {
        let base = try tempDir().appendingPathComponent("Sequence")
        var list = VaultList()
        _ = try list.create(named: "a", in: base)
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("a").path))
    }

    @Test func creatingRejectsBadAndExistingNames() throws {
        let base = try tempDir()
        var list = VaultList()
        #expect(throws: LibraryOperationError.invalidName) { try list.create(named: "  ", in: base) }
        #expect(throws: LibraryOperationError.invalidName) { try list.create(named: "a/b", in: base) }
        _ = try list.create(named: "a", in: base)
        #expect(throws: LibraryOperationError.alreadyExists) { try list.create(named: "a", in: base) }
    }

    @Test func removingForgetsTheVaultButKeepsItsFiles() throws {
        let base = try tempDir()
        var list = VaultList()
        let vault = try list.create(named: "a", in: base)
        list.remove(vault.id)
        #expect(list.vaults.isEmpty)
        #expect(FileManager.default.fileExists(atPath: vault.url.path))
    }

    @Test func renamingChangesOnlyTheDisplayName() throws {
        var list = VaultList()
        let vault = list.add(folder: URL(fileURLWithPath: "/tmp/notes"))
        list.rename(vault.id, to: " Notes ")
        #expect(list.vaults[0].name == "Notes")
        #expect(list.vaults[0].path == vault.path)
        list.rename(vault.id, to: "  ")
        #expect(list.vaults[0].name == "Notes")
    }

    @Test func savedListLoadsBackAndMissingFileIsEmpty() throws {
        let file = try tempDir().appendingPathComponent("vaults.json")
        #expect(VaultList.load(from: file).vaults.isEmpty)
        var list = VaultList()
        _ = list.add(folder: URL(fileURLWithPath: "/tmp/notes"))
        try list.save(to: file)
        #expect(VaultList.load(from: file) == list)
    }
}
