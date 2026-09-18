import { storage } from "../storage";

// Correlation recomputes are debounced per user so a burst of writes (a
// batch of symptoms, a settings change) results in one pass that runs after
// the response has been sent.
const DEBOUNCE_MS = 3000;
const pending = new Map<string, NodeJS.Timeout>();

export function requestRecompute(userId: string, delayMs = DEBOUNCE_MS): void {
  const existing = pending.get(userId);
  if (existing) clearTimeout(existing);
  const timer = setTimeout(() => {
    pending.delete(userId);
    storage.regenerateCorrelations(userId).catch((error) => {
      console.error(`Correlation recompute failed for user ${userId}:`, error);
    });
  }, delayMs);
  timer.unref?.();
  pending.set(userId, timer);
}

// Waits for any pending recompute of this user to finish (used by tests)
export async function flushRecompute(userId: string): Promise<void> {
  const existing = pending.get(userId);
  if (!existing) return;
  clearTimeout(existing);
  pending.delete(userId);
  await storage.regenerateCorrelations(userId);
}
