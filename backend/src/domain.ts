type Brand<T, B extends string> = T & { readonly __brand: B };

export type RecordingId = Brand<string, "RecordingId">;
/** Server-wide write sequence. Every write anywhere takes MAX + 1, so it is both the per-recording conflict token and the feed cursor. */
export type Version = Brand<number, "Version">;
export type DeviceId = Brand<string, "DeviceId">;
/** The client's mutation id. Same edit, same key, on every retry and across app restarts. */
export type IdempotencyKey = Brand<string, "IdempotencyKey">;
export type PageLimit = Brand<number, "PageLimit">;

export const EDITABLE_FIELDS = ["title", "summary"] as const;
export type EditableField = (typeof EDITABLE_FIELDS)[number];

export const LIMITS = {
  defaultPage: 100,
  maxPage: 500,
  titleChars: 300,
  summaryChars: 20_000,
  appliedOpsRetentionMs: 30 * 24 * 60 * 60 * 1000,
} as const;

/** At least one editable field. `{}` does not type-check. */
export type FieldEdits = {
  [K in EditableField]: Pick<Record<EditableField, string>, K> & Partial<Record<EditableField, string>>;
}[EditableField];

export interface TranscriptSegment {
  readonly startMs: number;
  readonly text: string;
}

export interface LiveRecording {
  readonly kind: "live";
  readonly id: RecordingId;
  readonly title: string;
  readonly summary: string;
  readonly version: Version;
  readonly createdAt: number;
  readonly updatedAt: number;
  /** Device that made the last write; null for seeded rows. */
  readonly updatedBy: DeviceId | null;
  readonly segmentCount: number;
}

export interface DeletedRecording {
  readonly kind: "deleted";
  readonly id: RecordingId;
  readonly version: Version;
  readonly updatedAt: number;
  readonly updatedBy: DeviceId | null;
}

/** What the feed ships: never a transcript. */
export type RecordingHead = LiveRecording | DeletedRecording;

export interface RecordingDetail {
  readonly head: LiveRecording;
  /** Immutable. Fetched once per recording and cached by the client. */
  readonly transcript: readonly TranscriptSegment[];
}

export interface Cursor {
  /** Identifies this database instance, so a cursor from a wiped DB is detected instead of silently skipping rows. */
  readonly epoch: string;
  readonly after: Version | 0;
}

export interface Page {
  readonly items: readonly RecordingHead[];
  readonly next: Cursor;
  readonly hasMore: boolean;
}

export type ListResult = { readonly kind: "page"; readonly page: Page } | { readonly kind: "cursor_reset" };

/** Position in the browse order (newest first). created_at is immutable, so a row never moves. */
export interface BrowseCursor {
  readonly epoch: string;
  readonly createdAt: number;
  readonly id: RecordingId;
}

export interface BrowsePage {
  readonly items: readonly LiveRecording[];
  readonly next: BrowseCursor | null;
  readonly hasMore: boolean;
  /** Feed cursor at the moment this page was read: changes after it reach the device through `list`. */
  readonly sync: Cursor;
}

export type BrowseResult = { readonly kind: "page"; readonly page: BrowsePage } | { readonly kind: "cursor_reset" };

export interface FieldConflict {
  readonly field: EditableField;
  /** Current server value. */
  readonly theirs: string;
  readonly changedBy: DeviceId | null;
  readonly changedAt: number;
}

interface WriteCommand {
  readonly id: RecordingId;
  readonly baseVersion: Version;
  readonly key: IdempotencyKey;
  readonly device: DeviceId;
}

export interface EditCommand extends WriteCommand {
  readonly edits: FieldEdits;
}

export type DeleteCommand = WriteCommand;

/** What a successful write returns. Stored verbatim in the ledger and replayed on a retried key. */
export type AppliedResult =
  | { readonly kind: "edited"; readonly recording: LiveRecording; readonly changed: readonly EditableField[] }
  | { readonly kind: "deleted"; readonly recording: DeletedRecording };

export type WriteOutcome =
  | { readonly kind: "applied"; readonly result: AppliedResult; readonly replayed: boolean }
  | { readonly kind: "conflict"; readonly fields: readonly [FieldConflict, ...FieldConflict[]]; readonly current: LiveRecording }
  | { readonly kind: "gone"; readonly current: DeletedRecording }
  | { readonly kind: "not_found" }
  | { readonly kind: "key_reused" }
  | { readonly kind: "base_ahead"; readonly current: RecordingHead };

export interface NewRecording {
  readonly id: RecordingId;
  readonly title: string;
  readonly summary: string;
  readonly createdAt: number;
  readonly transcript: readonly TranscriptSegment[];
}
