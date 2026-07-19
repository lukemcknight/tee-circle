export async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

export function timingSafeStringEqual(a: string, b: string): boolean {
  const aBytes = new TextEncoder().encode(a);
  const bBytes = new TextEncoder().encode(b);
  const length = Math.max(aBytes.length, bBytes.length);
  let difference = aBytes.length ^ bBytes.length;
  for (let index = 0; index < length; index += 1) {
    difference |= (aBytes[index] ?? 0) ^ (bBytes[index] ?? 0);
  }
  return difference === 0;
}
