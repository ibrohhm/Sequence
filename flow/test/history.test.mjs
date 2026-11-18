import { test } from "node:test";
import assert from "node:assert/strict";
import { createHistory } from "../src/history.js";

test("undo with nothing recorded returns null and canUndo is false", () => {
  const h = createHistory();
  assert.equal(h.undo("now"), null);
  assert.equal(h.canUndo, false);
  assert.equal(h.canRedo, false);
});

test("undo returns the last recorded state; redo returns the state undo left", () => {
  const h = createHistory();
  h.record("A");
  h.record("B");
  assert.equal(h.undo("C"), "B");
  assert.equal(h.undo("B"), "A");
  assert.equal(h.undo("A"), null);
  assert.equal(h.redo("A"), "B");
  assert.equal(h.redo("B"), "C");
  assert.equal(h.redo("C"), null);
});

test("a new edit after undo discards what could have been redone", () => {
  const h = createHistory();
  h.record("A");
  h.undo("B");
  assert.equal(h.canRedo, true);
  h.record("A");
  assert.equal(h.canRedo, false);
});

test("the oldest states drop once the limit is reached", () => {
  const h = createHistory(3);
  for (const s of ["1", "2", "3", "4"]) h.record(s);
  assert.equal(h.undo("5"), "4");
  assert.equal(h.undo("4"), "3");
  assert.equal(h.undo("3"), "2");
  assert.equal(h.undo("2"), null);
});

test("reset forgets everything", () => {
  const h = createHistory();
  h.record("A");
  h.undo("B");
  h.reset();
  assert.equal(h.canUndo, false);
  assert.equal(h.canRedo, false);
});
