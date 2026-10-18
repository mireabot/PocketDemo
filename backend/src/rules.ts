import {
  EDITABLE_FIELDS,
  type DeviceId,
  type EditableField,
  type FieldConflict,
  type FieldEdits,
  type Version,
} from "./domain";

export interface FieldState {
  readonly value: string;
  /** Version of the write that last changed this field. */
  readonly version: Version;
  readonly by: DeviceId | null;
  readonly at: number;
}

export interface RowState {
  readonly version: Version;
  readonly fields: Readonly<Record<EditableField, FieldState>>;
}

export type EditDecision =
  | { readonly kind: "write"; readonly set: FieldEdits }
  | { readonly kind: "noop" }
  | { readonly kind: "conflict"; readonly fields: readonly [FieldConflict, ...FieldConflict[]] }
  | { readonly kind: "base_ahead" };

export type DeleteDecision =
  | { readonly kind: "delete" }
  | { readonly kind: "conflict"; readonly fields: readonly [FieldConflict, ...FieldConflict[]] }
  | { readonly kind: "base_ahead" };

/**
 * A field someone else changed after the client's base. Another device's write is what makes an
 * edit stale; this device's own earlier writes never do, so a queue of edits sent in order with
 * their original base versions doesn't conflict with itself.
 */
function changedByOther(field: FieldState, baseVersion: Version, device: DeviceId): boolean {
  return field.version > baseVersion && field.by !== device;
}

function toConflict(field: EditableField, state: FieldState): FieldConflict {
  return { field, theirs: state.value, changedBy: state.by, changedAt: state.at };
}

function nonEmpty<T>(items: T[]): items is [T, ...T[]] {
  return items.length > 0;
}

/**
 * Per field the edit sets: equal to the server value is a no-op, changed by another device since
 * the base is a conflict, otherwise a write. Any conflict rejects the whole edit.
 */
export function decideEdit({ row, baseVersion, device, edits }: {
  row: RowState;
  baseVersion: Version;
  device: DeviceId;
  edits: FieldEdits;
}): EditDecision {
  if (baseVersion > row.version) return { kind: "base_ahead" };

  const conflicts: FieldConflict[] = [];
  const set: Partial<Record<EditableField, string>> = {};
  for (const field of EDITABLE_FIELDS) {
    const wanted = edits[field];
    if (wanted === undefined) continue;
    const state = row.fields[field];
    if (state.value === wanted) continue;
    if (changedByOther(state, baseVersion, device)) conflicts.push(toConflict(field, state));
    else set[field] = wanted;
  }

  if (nonEmpty(conflicts)) return { kind: "conflict", fields: conflicts };
  if (set.title !== undefined) return { kind: "write", set: { ...set, title: set.title } };
  if (set.summary !== undefined) return { kind: "write", set: { ...set, summary: set.summary } };
  return { kind: "noop" };
}

/** A delete would silently discard any field another device changed after the base, so that is a conflict. */
export function decideDelete({ row, baseVersion, device }: {
  row: RowState;
  baseVersion: Version;
  device: DeviceId;
}): DeleteDecision {
  if (baseVersion > row.version) return { kind: "base_ahead" };
  const conflicts = EDITABLE_FIELDS.filter((field) => changedByOther(row.fields[field], baseVersion, device)).map(
    (field) => toConflict(field, row.fields[field]),
  );
  return nonEmpty(conflicts) ? { kind: "conflict", fields: conflicts } : { kind: "delete" };
}
