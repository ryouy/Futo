/** テストで時刻を差し替えられるようにする。期限の判定はすべてサーバー時刻（この関数）で行う。 */
let override: (() => Date) | null = null;

export const now = (): Date => (override ? override() : new Date());

export function setClockForTests(fn: (() => Date) | null): void {
  override = fn;
}

export const addDays = (date: Date, days: number): Date => new Date(date.getTime() + days * 86_400_000);
export const addHours = (date: Date, hours: number): Date => new Date(date.getTime() + hours * 3_600_000);

/** 日次上限のキー（UTCの日付）。 */
export const dayKey = (date: Date): string => date.toISOString().slice(0, 10).replace(/-/g, "");
