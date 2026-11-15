import { mkdtemp, mkdir, writeFile, realpath } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import type { Vault } from "../src/vaults.ts";

export async function makeVault(
  files: Record<string, string>,
  opts: { git?: boolean; name?: string } = {},
): Promise<Vault> {
  const dir = await realpath(await mkdtemp(join(tmpdir(), "vault-")));
  for (const [rel, content] of Object.entries(files)) {
    await mkdir(dirname(join(dir, rel)), { recursive: true });
    await writeFile(join(dir, rel), content);
  }
  if (opts.git) {
    const git = (...args: string[]) => execFileSync("git", args, { cwd: dir, stdio: "pipe" });
    git("init", "-q");
    git("config", "user.email", "test@example.com");
    git("config", "user.name", "Test");
    git("add", "-A");
    git("commit", "-q", "--allow-empty", "-m", "baseline");
  }
  const name = opts.name ?? dir.split("/").pop()!;
  return { id: name, name, path: dir };
}

export async function vaultsFile(vaults: Vault[]): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "vaults-json-"));
  const file = join(dir, "vaults.json");
  await writeFile(file, JSON.stringify({ vaults }));
  return file;
}
