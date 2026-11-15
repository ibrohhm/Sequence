import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { commitFile, isRepo, snapshotIfDirty, withVaultLock } from "../src/git.ts";
import { makeVault } from "./helpers.ts";

const git = (cwd: string, ...args: string[]) => execFileSync("git", args, { cwd, encoding: "utf8" }).trim();

test("isRepo is false for a plain dir and true for a repo", async () => {
  assert.equal(await isRepo((await makeVault({ "a.md": "x" })).path), false);
  assert.equal(await isRepo((await makeVault({ "a.md": "x" }, { git: true })).path), true);
});

test("commitFile commits only the target file", async () => {
  const v = await makeVault({ "a.md": "1", "b.md": "1" }, { git: true });
  await writeFile(join(v.path, "a.md"), "2");
  await writeFile(join(v.path, "b.md"), "2");
  const r = await commitFile(v, "a.md", "mcp: edit a.md");
  assert.equal(r.committed, true);
  assert.equal(git(v.path, "log", "-1", "--format=%s"), "mcp: edit a.md");
  assert.match(git(v.path, "status", "--porcelain"), /b\.md/);
  assert.doesNotMatch(git(v.path, "status", "--porcelain"), /a\.md/);
});

test("commitFile handles names with spaces and dots", async () => {
  const v = await makeVault({ "0. qris meeting prep.md": "1" }, { git: true });
  await writeFile(join(v.path, "0. qris meeting prep.md"), "2");
  assert.equal((await commitFile(v, "0. qris meeting prep.md", "mcp: edit x")).committed, true);
});

test("commitFile reports committed:false when nothing changed", async () => {
  const v = await makeVault({ "a.md": "1" }, { git: true });
  assert.equal((await commitFile(v, "a.md", "mcp: edit a.md")).committed, false);
});

test("snapshotIfDirty commits only when the file is dirty", async () => {
  const v = await makeVault({ "a.md": "1" }, { git: true });
  assert.equal((await snapshotIfDirty(v, "a.md")).committed, false);
  await writeFile(join(v.path, "a.md"), "user edit");
  assert.equal((await snapshotIfDirty(v, "a.md")).committed, true);
  assert.equal(git(v.path, "log", "-1", "--format=%s"), "mcp: snapshot a.md before edit");
});

test("snapshotIfDirty commits an untracked file", async () => {
  const v = await makeVault({ "a.md": "1" }, { git: true });
  await writeFile(join(v.path, "new.md"), "fresh");
  assert.equal((await snapshotIfDirty(v, "new.md")).committed, true);
});

test("a vault nested in a parent repo commits into the parent repo", async () => {
  const parent = await makeVault({ "readme.md": "x" }, { git: true });
  await mkdir(join(parent.path, "vault"));
  await writeFile(join(parent.path, "vault", "a.md"), "1");
  const nested = { id: "n", name: "n", path: join(parent.path, "vault") };
  assert.equal((await commitFile(nested, "a.md", "mcp: create a.md")).committed, true);
  assert.equal(git(parent.path, "log", "-1", "--format=%s"), "mcp: create a.md");
});

test("withVaultLock runs calls one after the other", async () => {
  const v = await makeVault({});
  const events: string[] = [];
  const slow = withVaultLock(v, async () => { events.push("a-start"); await new Promise((r) => setTimeout(r, 50)); events.push("a-end"); });
  const fast = withVaultLock(v, async () => { events.push("b-start"); events.push("b-end"); });
  await Promise.all([slow, fast]);
  assert.deepEqual(events, ["a-start", "a-end", "b-start", "b-end"]);
});

test("withVaultLock keeps running after a failed call", async () => {
  const v = await makeVault({});
  await assert.rejects(withVaultLock(v, async () => { throw new Error("boom"); }));
  assert.equal(await withVaultLock(v, async () => 7), 7);
});
