import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { VaultError } from "./errors.ts";

export type Vault = { id: string; name: string; path: string };

const DEFAULT_FILE = join(homedir(), "Library", "Application Support", "Sequence", "vaults.json");

export async function loadVaults(file: string = process.env.SEQUENCE_VAULTS_FILE ?? DEFAULT_FILE): Promise<Vault[]> {
  let text: string;
  try {
    text = await readFile(file, "utf8");
  } catch {
    throw new VaultError(`Cannot read vault list at ${file}. Open Sequence and add a vault first.`);
  }
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    throw new VaultError(`Vault list at ${file} is not valid JSON.`);
  }
  const list = (data as { vaults?: unknown })?.vaults;
  if (!Array.isArray(list)) throw new VaultError(`Vault list at ${file} has no "vaults" array.`);
  return list.map((v) => {
    const { id, name, path } = v as Partial<Vault>;
    if (typeof name !== "string" || typeof path !== "string") throw new VaultError(`Vault list at ${file} has an entry without name or path.`);
    return { id: String(id ?? name), name, path };
  });
}

export function pickVault(vaults: Vault[], name?: string): Vault {
  const names = vaults.map((v) => v.name).join(", ") || "(none)";
  if (name === undefined) {
    if (vaults.length === 1) return vaults[0];
    throw new VaultError(`Which vault? Available: ${names}`);
  }
  const found = vaults.find((v) => v.name.toLowerCase() === name.toLowerCase());
  if (!found) throw new VaultError(`No vault named "${name}". Available: ${names}`);
  return found;
}
