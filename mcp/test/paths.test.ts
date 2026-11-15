import { test } from "node:test";
import assert from "node:assert/strict";
import { symlink } from "node:fs/promises";
import { join } from "node:path";
import { resolveInVault } from "../src/paths.ts";
import { VaultError } from "../src/errors.ts";
import { makeVault } from "./helpers.ts";

test("accepts a relative path and the same path as absolute", async () => {
  const v = await makeVault({ "qris/settlement.puml": "x" });
  const rel = await resolveInVault(v, "qris/settlement.puml");
  assert.equal(rel.rel, "qris/settlement.puml");
  const abs = await resolveInVault(v, join(v.path, "qris/settlement.puml"));
  assert.equal(abs.rel, "qris/settlement.puml");
});

test("accepts names with spaces and dots", async () => {
  const v = await makeVault({ "0. qris meeting prep.md": "x" });
  const r = await resolveInVault(v, "0. qris meeting prep.md");
  assert.equal(r.rel, "0. qris meeting prep.md");
});

test("accepts a path whose file does not exist yet", async () => {
  const v = await makeVault({ "qris/a.puml": "x" });
  const r = await resolveInVault(v, "qris/new.puml");
  assert.equal(r.rel, "qris/new.puml");
});

for (const bad of ["../x.md", ".git/config", "a/.hidden/b.md", "notes.txt"]) {
  test(`rejects ${bad}`, async () => {
    const v = await makeVault({ "a/b.md": "x" });
    await assert.rejects(resolveInVault(v, bad), VaultError);
  });
}

test("rejects an absolute path outside the vault", async () => {
  const v = await makeVault({ "a.md": "x" });
  await assert.rejects(resolveInVault(v, "/etc/hosts.md"), VaultError);
});

test("rejects a symlink pointing outside the vault", async () => {
  const outside = await makeVault({ "secret.md": "s" });
  const v = await makeVault({ "a.md": "x" });
  await symlink(join(outside.path, "secret.md"), join(v.path, "link.md"));
  await assert.rejects(resolveInVault(v, "link.md"), VaultError);
});
