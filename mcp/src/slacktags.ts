import type { DatabaseSync } from "node:sqlite";

export type TagRow = {
  id: string;
  name: string;
  kind: "board" | "list";
  slack_list: "none" | "todo" | "saved";
  reactions: string[];
  columns: string[];
};

type RawTag = Omit<TagRow, "reactions" | "columns"> & { reactions: string; columns: string };

function parse(tag: RawTag): TagRow {
  return { id: tag.id, name: tag.name, kind: tag.kind, slack_list: tag.slack_list, reactions: JSON.parse(tag.reactions), columns: JSON.parse(tag.columns) };
}

export function listSlackTags(db: DatabaseSync): TagRow[] {
  return (db.prepare("SELECT id, name, kind, slack_list, reactions, columns FROM tags ORDER BY position, id").all() as RawTag[]).map(parse);
}

export function getSlackTag(db: DatabaseSync, id: string): TagRow | undefined {
  const row = db.prepare("SELECT id, name, kind, slack_list, reactions, columns FROM tags WHERE id = ?").get(id) as RawTag | undefined;
  return row && parse(row);
}
