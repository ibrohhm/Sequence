import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFile, stat, symlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { createProject, createTopic, editTopic, overwriteTopic } from "../src/write.ts";
import { VaultError } from "../src/errors.ts";
import { makeVault } from "./helpers.ts";

const git = (cwd: string, ...args: string[]) => execFileSync("git", args, { cwd, encoding: "utf8" }).trim();
const exists = (p: string) => stat(p).then(() => true, () => false);

test("createTopic writes the file and commits it", async () => {
  const v = await makeVault({ "qris/a.puml": "x" }, { git: true });
  const r = await createTopic([v], "qris", "settlement.puml", "@startuml\n@enduml");
  assert.deepEqual([r.path, r.committed, r.snapshot], ["qris/settlement.puml", true, false]);
  assert.equal(await readFile(join(v.path, "qris/settlement.puml"), "utf8"), "@startuml\n@enduml");
  assert.equal(git(v.path, "log", "-1", "--format=%s"), "mcp: create qris/settlement.puml");
});

test("createTopic refuses existing file, missing project, bad name and big content", async () => {
  const v = await makeVault({ "qris/a.puml": "x" }, { git: true });
  await assert.rejects(createTopic([v], "qris", "a.puml", "y"), VaultError);
  await assert.rejects(createTopic([v], "nope", "b.puml", "y"), VaultError);
  await assert.rejects(createTopic([v], "qris", "noext", "y"), VaultError);
  await assert.rejects(createTopic([v], "qris", "../b.puml", "y"), VaultError);
  await assert.rejects(createTopic([v], "qris", "big.md", "x".repeat(1024 * 1024 + 1)), VaultError);
  assert.equal(await readFile(join(v.path, "qris/a.puml"), "utf8"), "x");
  assert.equal(await exists(join(v.path, "qris/b.puml")), false);
  assert.equal(await exists(join(v.path, "qris/big.md")), false);
});

test("createProject makes a folder and refuses duplicates and bad names", async () => {
  const v = await makeVault({ "qris/a.md": "x" }, { git: true });
  await createProject([v], "new-project");
  assert.equal((await stat(join(v.path, "new-project"))).isDirectory(), true);
  await assert.rejects(createProject([v], "qris"), VaultError);
  await assert.rejects(createProject([v], "a/b"), VaultError);
  await assert.rejects(createProject([v], ".hidden"), VaultError);
});

test("editTopic replaces exactly one occurrence and commits", async () => {
  const v = await makeVault({ "p/a.md": "one two three" }, { git: true });
  const r = await editTopic([v], "p/a.md", "two", "2");
  assert.equal(r.committed, true);
  assert.equal(await readFile(join(v.path, "p/a.md"), "utf8"), "one 2 three");
  assert.equal(git(v.path, "log", "-1", "--format=%s"), "mcp: edit p/a.md");
});

test("editTopic fails with the count for zero or several matches and leaves the file", async () => {
  const v = await makeVault({ "p/a.md": "x x" }, { git: true });
  await assert.rejects(editTopic([v], "p/a.md", "x", "y"), (e: Error) => e instanceof VaultError && e.message.includes("2"));
  await assert.rejects(editTopic([v], "p/a.md", "zzz", "y"), (e: Error) => e instanceof VaultError && e.message.includes("0"));
  assert.equal(await readFile(join(v.path, "p/a.md"), "utf8"), "x x");
});

test("editTopic rejects an empty old string", async () => {
  const v = await makeVault({ "p/a.md": "x" }, { git: true });
  await assert.rejects(editTopic([v], "p/a.md", "", "y"), VaultError);
});

test("editTopic matches CRLF content as stored", async () => {
  const v = await makeVault({ "p/a.md": "a\r\nb\r\nc" }, { git: true });
  await editTopic([v], "p/a.md", "a\r\nb", "X");
  assert.equal(await readFile(join(v.path, "p/a.md"), "utf8"), "X\r\nc");
});

test("editTopic snapshots the user's pending changes first so the edit can be reverted", async () => {
  const v = await makeVault({ "p/a.md": "base" }, { git: true });
  await writeFile(join(v.path, "p/a.md"), "user wrote this");
  const r = await editTopic([v], "p/a.md", "wrote", "typed");
  assert.equal(r.snapshot, true);
  assert.deepEqual(git(v.path, "log", "-2", "--format=%s").split("\n"), ["mcp: edit p/a.md", "mcp: snapshot p/a.md before edit"]);
  git(v.path, "revert", "--no-edit", "HEAD");
  assert.equal(await readFile(join(v.path, "p/a.md"), "utf8"), "user wrote this");
});

test("overwriteTopic replaces content and refuses a missing file", async () => {
  const v = await makeVault({ "p/a.md": "old" }, { git: true });
  await overwriteTopic([v], "p/a.md", "new");
  assert.equal(await readFile(join(v.path, "p/a.md"), "utf8"), "new");
  assert.equal(git(v.path, "log", "-1", "--format=%s"), "mcp: overwrite p/a.md");
  await assert.rejects(overwriteTopic([v], "p/missing.md", "x"), VaultError);
});

test("writes into a vault that is not a git repo are refused and write nothing", async () => {
  const v = await makeVault({ "p/a.md": "old" });
  await assert.rejects(overwriteTopic([v], "p/a.md", "new"), (e: Error) => e instanceof VaultError && e.message.includes("git init"));
  await assert.rejects(createTopic([v], "p", "b.md", "x"), (e: Error) => e instanceof VaultError && e.message.includes("git init"));
  assert.equal(await readFile(join(v.path, "p/a.md"), "utf8"), "old");
  assert.equal(await exists(join(v.path, "p/b.md")), false);
});

test("concurrent edits to different files in one vault both commit", async () => {
  const v = await makeVault({ "p/a.md": "a", "p/b.md": "b" }, { git: true });
  const [x, y] = await Promise.all([editTopic([v], "p/a.md", "a", "A"), editTopic([v], "p/b.md", "b", "B")]);
  assert.equal(x.committed && y.committed, true);
  assert.equal(git(v.path, "status", "--porcelain"), "");
});

test("a git-ignored file is written but reports the commit failure", async () => {
  const v = await makeVault({ ".gitignore": "p/ignored.md\n", "p/ignored.md": "old", "p/keep.md": "k" }, { git: true });
  const r = await overwriteTopic([v], "p/ignored.md", "new");
  assert.equal(r.committed, false);
  assert.ok(r.commitError);
  assert.equal(await readFile(join(v.path, "p/ignored.md"), "utf8"), "new");
});

test("edit with an ambiguous path across vaults needs a vault", async () => {
  const a = await makeVault({ "p/a.md": "1" }, { git: true, name: "one" });
  const b = await makeVault({ "p/a.md": "1" }, { git: true, name: "two" });
  await assert.rejects(editTopic([a, b], "p/a.md", "1", "2"), (e: Error) => e instanceof VaultError && e.message.includes("one") && e.message.includes("two"));
  await editTopic([a, b], "p/a.md", "1", "2", "two");
  assert.equal(await readFile(join(b.path, "p/a.md"), "utf8"), "2");
  assert.equal(await readFile(join(a.path, "p/a.md"), "utf8"), "1");
});

test("a file name that looks like a git pathspec commits only that file", async () => {
  const v = await makeVault({ "p/a.md": "1", "p/notes d.md": "1", "c.md": "1" }, { git: true });
  await writeFile(join(v.path, "c.md"), "user change");
  await writeFile(join(v.path, "p/a.md"), "user change");
  await writeFile(join(v.path, "p/notes d.md"), "user change");
  await createTopic([v], "p", "notes [draft].md", "x");
  await createTopic([v], "p", "*.md", "x");
  await createTopic([v], "p", ":!x.md", "x");
  assert.deepEqual(git(v.path, "diff", "--name-only").split("\n").sort(), ["c.md", "p/a.md", "p/notes d.md"]);
  assert.equal(git(v.path, "diff", "--cached", "--name-only"), "");
  assert.equal(git(v.path, "show", "--name-only", "--format=", "HEAD"), "p/:!x.md");
});

test("createTopic refuses an empty project name", async () => {
  const v = await makeVault({ "p/a.md": "1" }, { git: true });
  await assert.rejects(createTopic([v], "", "x.md", "x"), VaultError);
  assert.equal(await exists(join(v.path, "x.md")), false);
});

test("editing through a symlinked topic snapshots and commits the real file", async () => {
  const v = await makeVault({ "real.md": "base", "p/a.md": "1" }, { git: true });
  await symlink(join(v.path, "real.md"), join(v.path, "p/link.md"));
  await writeFile(join(v.path, "real.md"), "user work");
  const r = await editTopic([v], "p/link.md", "work", "stuff");
  assert.equal(r.snapshot, true);
  assert.equal(r.committed, true);
  assert.equal(git(v.path, "show", "--name-only", "--format=", "HEAD"), "real.md");
  assert.equal(git(v.path, "status", "--porcelain"), "?? p/link.md");
});

test("a symlinked folder into a hidden directory is refused", async () => {
  const v = await makeVault({ "p/a.md": "1" }, { git: true });
  await symlink(join(v.path, ".git"), join(v.path, "docs"));
  await assert.rejects(createTopic([v], "docs", "x.md", "x"), VaultError);
  assert.equal(await exists(join(v.path, ".git", "x.md")), false);
});
