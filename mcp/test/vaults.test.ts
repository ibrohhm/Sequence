import { test } from "node:test";
import assert from "node:assert/strict";
import { writeFile } from "node:fs/promises";
import { loadVaults, pickVault } from "../src/vaults.ts";
import { VaultError } from "../src/errors.ts";
import { makeVault, vaultsFile } from "./helpers.ts";

test("loadVaults reads the vaults file", async () => {
  const v = await makeVault({}, { name: "alpha" });
  const vaults = await loadVaults(await vaultsFile([v]));
  assert.equal(vaults.length, 1);
  assert.equal(vaults[0].name, "alpha");
});

test("loadVaults rejects a missing file with VaultError", async () => {
  await assert.rejects(loadVaults("/nonexistent/vaults.json"), VaultError);
});

test("loadVaults rejects malformed JSON with VaultError", async () => {
  const f = await vaultsFile([]);
  await writeFile(f, "{not json");
  await assert.rejects(loadVaults(f), VaultError);
});

test("pickVault with two vaults and no name lists both names", async () => {
  const a = await makeVault({}, { name: "alpha" });
  const b = await makeVault({}, { name: "beta" });
  assert.throws(() => pickVault([a, b]), (e: Error) => e instanceof VaultError && e.message.includes("alpha") && e.message.includes("beta"));
});

test("pickVault matches name ignoring case", async () => {
  const a = await makeVault({}, { name: "Alpha" });
  const b = await makeVault({}, { name: "beta" });
  assert.equal(pickVault([a, b], "alpha").name, "Alpha");
});

test("pickVault returns the only vault when no name is given", async () => {
  const a = await makeVault({}, { name: "alpha" });
  assert.equal(pickVault([a]).name, "alpha");
});
