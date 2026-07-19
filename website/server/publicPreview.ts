import {
  parsePublicPending,
  parsePublicPreview,
  previewErrorKind,
  type PublicPreviewErrorKind,
  type PublicTripPending,
  type PublicTripPreview,
} from '../src/liveTrip/publicPreview.js'

export interface PreviewResult {
  status: number
  preview?: PublicTripPreview
  pending?: PublicTripPending
  error?: PublicPreviewErrorKind
}

export type PreviewRequestHeaders = Record<string, string | string[] | undefined>

export interface PublicPreviewRequestContext {
  viewerIdentity?: string
}

export const PREVIEW_PROXY_SECRET_HEADER = 'x-teecircle-preview-proxy-secret'
export const PREVIEW_PROXY_VIEWER_HEADER = 'x-teecircle-preview-viewer'

const TOKEN_PATTERN = /^[A-Za-z0-9_-]{40,128}$/
const NETWORK_IDENTITY_PATTERN = /^[0-9a-f:.]{2,64}$/i

function firstHeaderValue(headers: PreviewRequestHeaders, name: string): string | undefined {
  const entry = Object.entries(headers).find(([key]) => key.toLowerCase() === name)
  const value = entry?.[1]
  return Array.isArray(value) ? value[0] : value
}

function cleanNetworkIdentity(value: string | undefined): string | undefined {
  // Vercel overwrites these headers with one public client IP. Splitting is a
  // defensive fallback for local/reverse-proxy development only.
  const candidate = value?.split(',')[0]?.trim()
  return candidate && NETWORK_IDENTITY_PATTERN.test(candidate) ? candidate : undefined
}

export function viewerIdentityFromVercelHeaders(
  headers: PreviewRequestHeaders,
): string | undefined {
  return cleanNetworkIdentity(
    firstHeaderValue(headers, 'x-vercel-forwarded-for')
      ?? firstHeaderValue(headers, 'x-forwarded-for')
      ?? firstHeaderValue(headers, 'x-real-ip'),
  )
}

export function validInviteToken(value: unknown): value is string {
  return typeof value === 'string' && TOKEN_PATTERN.test(value)
}

export async function fetchPublicPreview(
  inviteToken: string,
  context: PublicPreviewRequestContext = {},
): Promise<PreviewResult> {
  const supabaseUrl = process.env.SUPABASE_URL ?? process.env.VITE_SUPABASE_URL
  const endpoint = process.env.PUBLIC_PREVIEW_ENDPOINT
    ?? process.env.VITE_PUBLIC_PREVIEW_ENDPOINT
    ?? (supabaseUrl ? `${supabaseUrl.replace(/\/$/, '')}/functions/v1/preview-trip-v1` : undefined)
  if (!endpoint) return { status: 503, error: 'unavailable' }

  try {
    const proxySecret = process.env.PUBLIC_PREVIEW_PROXY_SECRET?.trim()
    const proxyHeaders: Record<string, string> = {}
    if (proxySecret && context.viewerIdentity) {
      proxyHeaders[PREVIEW_PROXY_SECRET_HEADER] = proxySecret
      proxyHeaders[PREVIEW_PROXY_VIEWER_HEADER] = context.viewerIdentity
    }

    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        ...proxyHeaders,
      },
      body: JSON.stringify({ schemaVersion: 1, inviteToken }),
      cache: 'no-store',
      redirect: 'error',
      signal: AbortSignal.timeout(8_000),
    })

    let payload: unknown
    try {
      payload = await response.json()
    } catch {
      return { status: 502, error: 'offline' }
    }

    if (!response.ok) {
      return {
        status: response.status,
        error: previewErrorKind(payload, response.status),
      }
    }

    const preview = parsePublicPreview(payload)
    if (preview) return { status: 200, preview }

    const pending = parsePublicPending(payload)
    return pending
      ? { status: 200, pending }
      : { status: 502, error: 'offline' }
  } catch {
    return { status: 503, error: 'offline' }
  }
}
