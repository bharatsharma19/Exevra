/** Time sources, injectable so handlers can be tested deterministically. */

/** Wall-clock milliseconds since the Unix epoch. */
export interface Clock {
  now(): number;
}

/** The real clock. */
export const systemClock: Clock = { now: () => Date.now() };

/**
 * Opaque timer handle. Deno returns numbers, but with npm type definitions loaded the globals may
 * be typed as Node's `Timeout`, so handles are treated as opaque values.
 */
export type TimerId = unknown;

/** Timer functions used for pings and timeouts. */
export interface Timers {
  setTimeout(callback: () => void, ms: number): TimerId;
  clearTimeout(id: TimerId): void;
  setInterval(callback: () => void, ms: number): TimerId;
  clearInterval(id: TimerId): void;
}

/** The real timers. */
export const systemTimers: Timers = {
  setTimeout: (callback: () => void, ms: number): TimerId => setTimeout(callback, ms),
  clearTimeout: (id: TimerId): void => clearTimeout(id as number | undefined),
  setInterval: (callback: () => void, ms: number): TimerId => setInterval(callback, ms),
  clearInterval: (id: TimerId): void => clearInterval(id as number | undefined),
};
