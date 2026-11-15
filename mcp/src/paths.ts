import { realpath } from "node:fs/promises";
import { basename, dirname, isAbsolute, join, normalize, relative, sep } from "node:path";
import { VaultError } from "./errors.ts";
import type { Vault } from "./vaults.ts";

export const EXTENSIONS = [".puml", ".plantuml", ".pu", ".wsd", ".md"];

function inside(root: string, target: string): boolean {
  return target === root || target.startsWith(root + sep);
}

export async function resolveInVault(vault: Vault, input: string): Promise<{ abs: string; rel: string }> {
  const root = await realpath(vault.path);
  let rel: string;
  if (isAbsolute(input)) {
    const base = [root, vault.path].find((b) => inside(b, normalize(input)));
    if (!base) throw new VaultError(`Path is outside vault "${vault.name}": ${input}`);
    rel = relative(base, normalize(input));
  } else {
    rel = normalize(input);
  }
  checkName(rel, input);

  const abs = join(root, rel);
  let real: string;
  try {
    real = await realpath(abs);
  } catch {
    let parent: string;
    try {
      parent = await realpath(dirname(abs));
    } catch {
      throw new VaultError(`Folder does not exist: ${dirname(rel)}`);
    }
    real = join(parent, basename(abs));
  }
  if (!inside(root, real)) throw new VaultError(`Path escapes vault "${vault.name}": ${input}`);
  const realRel = relative(root, real);
  checkName(realRel, input);
  return { abs: real, rel: realRel };
}

function checkName(rel: string, input: string): void {
  if (rel.split(sep).some((s) => s.startsWith("."))) throw new VaultError(`Hidden or parent path segments are not allowed: ${input}`);
  const ext = rel.slice(rel.lastIndexOf(".")).toLowerCase();
  if (!EXTENSIONS.includes(ext)) throw new VaultError(`Only ${EXTENSIONS.join(" ")} files are allowed: ${input}`);
}
