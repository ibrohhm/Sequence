import { test } from "node:test";
import assert from "node:assert/strict";
import { findTopic, listProjects, readTopic, searchContent } from "../src/find.ts";
import { VaultError } from "../src/errors.ts";
import { makeVault } from "./helpers.ts";

async function fixture() {
  const a = await makeVault({
    "qris-integration/qris-settlement-flow.puml": "@startuml\nA -> B : settle now\n@enduml",
    "qris-integration/qris-acquirer-flow.puml": "@startuml\nA -> B\n@enduml",
    "ppob/settlement.md": "# Settlement\nnotes",
    "0. qris meeting preparation with payment leads.md": "agenda: payment leads",
    ".git/config.md": "hidden",
  }, { name: "flows" });
  const b = await makeVault({ "ppob/settlement.md": "other vault" }, { name: "default" });
  return [a, b];
}

test("findTopic returns every settlement file", async () => {
  const hits = await findTopic(await fixture(), "settlement");
  assert.deepEqual(hits.map((h) => `${h.vault}:${h.path}`).sort(), [
    "default:ppob/settlement.md",
    "flows:ppob/settlement.md",
    "flows:qris-integration/qris-settlement-flow.puml",
  ]);
});

test("findTopic narrows by project", async () => {
  const hits = await findTopic(await fixture(), "settlement", { project: "QRIS-integration" });
  assert.equal(hits.length, 1);
  assert.equal(hits[0].project, "qris-integration");
});

test("findTopic narrows by vault", async () => {
  const hits = await findTopic(await fixture(), "settlement", { vault: "default" });
  assert.deepEqual(hits.map((h) => h.vault), ["default"]);
});

test("findTopic requires every token and finds names with spaces and dots", async () => {
  const hits = await findTopic(await fixture(), "qris meeting");
  assert.equal(hits.length, 1);
  assert.equal(hits[0].path, "0. qris meeting preparation with payment leads.md");
  assert.equal(hits[0].project, "");
  assert.equal((await findTopic(await fixture(), "qris nonexistent")).length, 0);
});

test("findTopic skips hidden folders", async () => {
  assert.equal((await findTopic(await fixture(), "config")).length, 0);
});

test("findTopic returns at most 10", async () => {
  const files: Record<string, string> = {};
  for (let i = 0; i < 15; i++) files[`p/topic-${i}.md`] = "x";
  assert.equal((await findTopic([await makeVault(files)], "topic")).length, 10);
});

test("searchContent returns the matching line", async () => {
  const hits = await searchContent(await fixture(), "settle now");
  assert.equal(hits.length, 1);
  assert.equal(hits[0].line, "A -> B : settle now");
});

test("listProjects lists top-level folders and skips .git", async () => {
  const [a] = await fixture();
  assert.deepEqual(await listProjects(a), ["ppob", "qris-integration"]);
});

test("readTopic reads a unique relative path", async () => {
  const vaults = await fixture();
  assert.match(await readTopic(vaults, "qris-integration/qris-acquirer-flow.puml"), /@startuml/);
});

test("readTopic with a path in two vaults and no vault names both", async () => {
  const vaults = await fixture();
  await assert.rejects(readTopic(vaults, "ppob/settlement.md"), (e: Error) => e instanceof VaultError && e.message.includes("flows") && e.message.includes("default"));
  assert.equal(await readTopic(vaults, "ppob/settlement.md", "default"), "other vault");
});

test("readTopic reads an absolute path copied from Sequence", async () => {
  const [a] = await fixture();
  assert.match(await readTopic([a], `${a.path}/ppob/settlement.md`), /Settlement/);
});

test("readTopic of a missing file throws VaultError", async () => {
  await assert.rejects(readTopic(await fixture(), "nope/missing.md"), VaultError);
});
