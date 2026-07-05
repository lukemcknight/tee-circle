/**
 * Retry utility with exponential backoff for network requests
 */

export type RetryOptions = {
  maxRetries?: number;
  baseDelayMs?: number;
  maxDelayMs?: number;
  shouldRetry?: (error: unknown) => boolean;
};

const DEFAULT_OPTIONS: Required<RetryOptions> = {
  maxRetries: 3,
  baseDelayMs: 300,
  maxDelayMs: 2000,
  shouldRetry: (error: unknown) => {
    // Don't retry on auth/permission errors (these won't resolve with retry)
    if (error && typeof error === 'object') {
      const err = error as { code?: string; message?: string; status?: number };
      // Supabase auth errors
      if (err.code === 'PGRST301' || err.code === '42501') return false; // Permission denied
      if (err.message?.includes('JWT') || err.message?.includes('token')) return false;
      if (err.status === 401 || err.status === 403) return false;
    }
    return true;
  },
};

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Executes a function with exponential backoff retry logic
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  options?: RetryOptions
): Promise<T> {
  const opts = { ...DEFAULT_OPTIONS, ...options };
  let lastError: unknown;

  for (let attempt = 0; attempt <= opts.maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;

      if (attempt === opts.maxRetries || !opts.shouldRetry(error)) {
        throw error;
      }

      // Exponential backoff: 1s, 2s, 4s, capped at maxDelayMs
      const delay = Math.min(opts.baseDelayMs * Math.pow(2, attempt), opts.maxDelayMs);
      await sleep(delay);
    }
  }

  throw lastError;
}

/**
 * Wraps a Supabase query result and retries on network errors
 * Returns null on permanent failures (auth/permission errors)
 * Works with both Promise and PromiseLike (Supabase query builders)
 */
export async function withSupabaseRetry<T>(
  queryFn: () => PromiseLike<{ data: T | null; error: { message: string; code?: string } | null }>,
  options?: RetryOptions
): Promise<{ data: T | null; error: { message: string; code?: string } | null; didRetry: boolean }> {
  const opts = { ...DEFAULT_OPTIONS, ...options };
  let lastError: { message: string; code?: string } | null = null;
  let didRetry = false;

  for (let attempt = 0; attempt <= opts.maxRetries; attempt++) {
    const result = await queryFn();

    if (!result.error) {
      return { data: result.data, error: null, didRetry };
    }

    lastError = result.error;

    // Check if this is a retryable error
    const isRetryable = opts.shouldRetry(result.error);

    if (attempt === opts.maxRetries || !isRetryable) {
      return { data: null, error: lastError, didRetry };
    }

    didRetry = true;
    const delay = Math.min(opts.baseDelayMs * Math.pow(2, attempt), opts.maxDelayMs);
    await sleep(delay);
  }

  return { data: null, error: lastError, didRetry };
}
