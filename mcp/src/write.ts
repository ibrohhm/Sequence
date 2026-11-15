import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { VaultError } from "./errors.ts";
import { locate } from "./find.ts";
import { commitFile, isRepo, snapshotIfDirty, withVaultLock } from "./git.ts";
import { EXTENSIONS, resolveInVault } from "./paths.ts";
import { pickVault, type Vault } from "./vaults.ts";

export type WriteResult = { path: string; committed: boolean; snapshot: boolean; commitError?: string };

const MAX_BYTES = 1024 * 1024;

function checkSize(content: string): void {
  if (Buffer.byteLength(content) > MAX_BYTES) throw new VaultError("Content is larger than 1 MB.");
}

async function requireRepo(vault: Vault): Promise<void> {
  if (!(await isRepo(vault.path))) throw new VaultError(`Vault "${vault.name}" is not a git repository. Run git init in ${vault.path} first.`);
}

async function commit(vault: Vault, rel: string, verb: string, snapshot: boolean): Promise<WriteResult> {
  try {
    const { committed } = await commitFile(vault, rel, `mcp: ${verb} ${rel}`);
    return { path: rel, committed, snapshot };
  } catch (e) {
    return { path: rel, committed: false, snapshot, commitError: (e as Error).message };
  }
}

async function rewrite(vaults: Vault[], input: string, vaultName: string | undefined, verb: string, next: (text: string) => string): Promise<WriteResult> {
  const { vault, abs, rel } = await locate(vaults, input, vaultName);
  await requireRepo(vault);
  return withVaultLock(vault, async () => {
    const updated = next(await readFile(abs, "utf8"));
    checkSize(updated);
    const { committed: snapshot } = await snapshotIfDirty(vault, rel);
    await writeFile(abs, updated);
    return commit(vault, rel, verb, snapshot);
  });
}

export async function createProject(vaults: Vault[], name: string, vaultName?: string): Promise<{ path: string }> {
  const vault = pickVault(vaults, vaultName);
  if (!name || /[\\/]/.test(name) || name.startsWith(".")) throw new VaultError(`Invalid project name: ${name}`);
  try {
    await mkdir(join(vault.path, name));
  } catch {
    throw new VaultError(`Project already exists or cannot be created: ${name}`);
  }
  return { path: name };
}

export async function createTopic(vaults: Vault[], project: string, name: string, content: string, vaultName?: string): Promise<WriteResult> {
  const vault = pickVault(vaults, vaultName);
  if (!project.trim()) throw new VaultError("Project must not be empty.");
  if (/[\\/]/.test(name)) throw new VaultError(`Topic name must not contain a path separator: ${name}`);
  if (!EXTENSIONS.some((e) => name.toLowerCase().endsWith(e))) throw new VaultError(`Topic name needs one of ${EXTENSIONS.join(" ")}: ${name}`);
  checkSize(content);
  const folder = await stat(join(vault.path, project)).catch(() => undefined);
  if (!folder?.isDirectory()) throw new VaultError(`Project folder does not exist: ${project}. Use create_project first.`);
  const { abs, rel } = await resolveInVault(vault, join(project, name));
  await requireRepo(vault);
  return withVaultLock(vault, async () => {
    try {
      await writeFile(abs, content, { flag: "wx" });
    } catch {
      throw new VaultError(`Topic already exists: ${rel}`);
    }
    return commit(vault, rel, "create", false);
  });
}

export async function editTopic(vaults: Vault[], input: string, old: string, replacement: string, vaultName?: string): Promise<WriteResult> {
  if (old === "") throw new VaultError("old must not be empty.");
  return rewrite(vaults, input, vaultName, "edit", (text) => {
    const count = text.split(old).length - 1;
    if (count !== 1) throw new VaultError(`old must occur exactly once; found ${count} occurrences.`);
    return text.replace(old, () => replacement);
  });
}

export async function overwriteTopic(vaults: Vault[], input: string, content: string, vaultName?: string): Promise<WriteResult> {
  return rewrite(vaults, input, vaultName, "overwrite", () => content);
}
