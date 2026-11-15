import { execFile } from "node:child_process";
import { realpath } from "node:fs/promises";
import { join, relative } from "node:path";
import { promisify } from "node:util";
import { VaultError } from "./errors.ts";
import type { Vault } from "./vaults.ts";

const run = promisify(execFile);

async function git(cwd: string, args: string[]): Promise<string> {
  try {
    return (await run("git", args, { cwd, env: { ...process.env, GIT_LITERAL_PATHSPECS: "1" } })).stdout;
  } catch (e) {
    const err = e as { stderr?: string; message: string };
    throw new VaultError(`git ${args[0]} failed: ${(err.stderr || err.message).trim()}`);
  }
}

export async function isRepo(dir: string): Promise<boolean> {
  try {
    return (await git(dir, ["rev-parse", "--is-inside-work-tree"])).trim() === "true";
  } catch {
    return false;
  }
}

async function target(vault: Vault, rel: string): Promise<{ top: string; file: string }> {
  const top = (await git(vault.path, ["rev-parse", "--show-toplevel"])).trim();
  const file = relative(await realpath(top), join(await realpath(vault.path), rel));
  return { top, file };
}

export async function commitFile(vault: Vault, rel: string, message: string): Promise<{ committed: boolean }> {
  const { top, file } = await target(vault, rel);
  await git(top, ["add", "--", file]);
  if ((await git(top, ["diff", "--cached", "--name-only", "--", file])).trim() === "") return { committed: false };
  await git(top, ["commit", "-q", "-m", message, "--", file]);
  return { committed: true };
}

export async function snapshotIfDirty(vault: Vault, rel: string): Promise<{ committed: boolean }> {
  const { top, file } = await target(vault, rel);
  if ((await git(top, ["status", "--porcelain", "--", file])).trim() === "") return { committed: false };
  return commitFile(vault, rel, `mcp: snapshot ${rel} before edit`);
}

const tails = new Map<string, Promise<unknown>>();

export function withVaultLock<T>(vault: Vault, fn: () => Promise<T>): Promise<T> {
  const prev = tails.get(vault.path) ?? Promise.resolve();
  const next = prev.then(fn, fn);
  tails.set(vault.path, next.catch(() => undefined));
  return next;
}
