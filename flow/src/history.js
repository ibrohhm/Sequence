/** Undo and redo stacks of states; a state is any value, here the serialized graph. */
export function createHistory(limit = 100) {
  let past = [];
  let future = [];
  return {
    /** Remember the state from before an edit; a new edit clears what could be redone. */
    record(state) {
      past.push(state);
      if (past.length > limit) past.shift();
      future = [];
    },
    /** The state to go back to, or null; `current` is kept for redo. */
    undo(current) {
      if (!past.length) return null;
      future.push(current);
      return past.pop();
    },
    redo(current) {
      if (!future.length) return null;
      past.push(current);
      return future.pop();
    },
    reset() {
      past = [];
      future = [];
    },
    get canUndo() {
      return past.length > 0;
    },
    get canRedo() {
      return future.length > 0;
    },
  };
}
