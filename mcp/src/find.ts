import { readdir, readFile, stat } from "node:fs/promises";
import { extname, join, sep } from "node:path";
import { VaultError } from "./errors.ts";
import { EXTENSIONS, resolveInVault } from "./paths.ts";
import { pickVault, type Vault } from "./vaults.ts";

export type Hit = { vault: string; project: string; path: string };
type Opts = { project?: string; vault?: string };

async function walk(dir: string, rel = ""): Promise<string[]> {
  const out: string[] = [];
  for (const entry of await readdir(join(dir, rel), { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    const next = rel ? join(rel, entry.name) : entry.name;
    if (entry.isDirectory()) out.push(...(await walk(dir, next)));
    else if (entry.isFile() && EXTENSIONS.includes(extname(entry.name).toLowerCase())) out.push(next);
  }
  return out;
}

function scope(vaults: Vault[], opts: Opts): Vault[] {
  return opts.vault === undefined ? vaults : [pickVault(vaults, opts.vault)];
}

function projectOf(rel: string): string {
  const parts = rel.split(sep);
  return parts.length > 1 ? parts[0] : "";
}

async function candidates(vaults: Vault[], opts: Opts): Promise<{ vault: Vault; rel: string }[]> {
  const out: { vault: Vault; rel: string }[] = [];
  for (const vault of scope(vaults, opts)) {
    for (const rel of await walk(vault.path)) {
      if (opts.project && projectOf(rel).toLowerCase() !== opts.project.toLowerCase()) continue;
      out.push({ vault, rel });
    }
  }
  return out;
}

export async function listProjects(vault: Vault): Promise<string[]> {
  const entries = await readdir(vault.path, { withFileTypes: true });
  return entries.filter((e) => e.isDirectory() && !e.name.startsWith(".")).map((e) => e.name).sort();
}

export async function findTopic(vaults: Vault[], query: string, opts: Opts = {}): Promise<Hit[]> {
  const tokens = query.toLowerCase().split(/\s+/).filter(Boolean);
  if (tokens.length === 0) return [];
  const scored: { hit: Hit; score: number }[] = [];
  for (const { vault, rel } of await candidates(vaults, opts)) {
    const file = rel.split(sep).pop()!;
    const name = file.slice(0, file.length - extname(file).length).toLowerCase();
    const positions = tokens.map((t) => name.indexOf(t));
    if (positions.some((p) => p < 0)) continue;
    scored.push({ hit: { vault: vault.name, project: projectOf(rel), path: rel }, score: positions.reduce((a, b) => a + b, 0) });
  }
  scored.sort((a, b) => a.score - b.score || a.hit.path.localeCompare(b.hit.path));
  return scored.slice(0, 10).map((s) => s.hit);
}

export async function searchContent(vaults: Vault[], query: string, opts: Opts = {}): Promise<(Hit & { line: string })[]> {
  const needle = query.toLowerCase();
  const out: (Hit & { line: string })[] = [];
  if (!needle) return out;
  for (const { vault, rel } of await candidates(vaults, opts)) {
    const text = await readFile(join(vault.path, rel), "utf8");
    const line = text.split(/\r?\n/).find((l) => l.toLowerCase().includes(needle));
    if (line !== undefined) out.push({ vault: vault.name, project: projectOf(rel), path: rel, line });
    if (out.length >= 20) break;
  }
  return out;
}

export async function locate(vaults: Vault[], input: string, vault?: string): Promise<{ vault: Vault; abs: string; rel: string }> {
  const pool = vault === undefined ? vaults : [pickVault(vaults, vault)];
  const found: { vault: Vault; abs: string; rel: string }[] = [];
  for (const v of pool) {
    try {
      const { abs, rel } = await resolveInVault(v, input);
      if ((await stat(abs)).isFile()) found.push({ vault: v, abs, rel });
    } catch {
      // not in this vault
    }
  }
  if (found.length === 0) throw new VaultError(`Topic not found: ${input}`);
  if (found.length > 1) throw new VaultError(`"${input}" exists in several vaults: ${found.map((f) => f.vault.name).join(", ")}. Pass vault.`);
  return found[0];
}

export async function readTopic(vaults: Vault[], input: string, vault?: string): Promise<string> {
  return readFile((await locate(vaults, input, vault)).abs, "utf8");
}
