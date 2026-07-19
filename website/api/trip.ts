import {
  fetchPublicPreview,
  validInviteToken,
  viewerIdentityFromVercelHeaders,
} from '../server/publicPreview.js'
import type {
  InitialPreviewPayload,
  PublicTripPending,
  PublicTripPreview,
} from '../src/liveTrip/publicPreview.js'

interface ApiRequest {
  method?: string
  query: Record<string, string | string[] | undefined>
  headers: Record<string, string | string[] | undefined>
}

interface ApiResponse {
  status(code: number): ApiResponse
  setHeader(name: string, value: string): void
  send(body: string): void
}

function htmlEscape(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;')
}

function safeJson(value: unknown): string {
  return JSON.stringify(value)
    .replace(/</g, '\\u003c')
    .replace(/>/g, '\\u003e')
    .replace(/&/g, '\\u0026')
}

function metadata(preview?: PublicTripPreview, pending?: PublicTripPending) {
  if (!preview) {
    if (pending) {
      return {
        title: `${pending.tripName} — Leaderboard | TeeCircle`,
        description: 'The TeeCircle standings are being prepared. Keep this page open for the first live update.',
      }
    }
    return {
      title: 'Live golf, together — TeeCircle',
      description: 'Follow the live leaderboard from TeeCircle.',
    }
  }

  const leader = preview.boards
    .find((board) => board.format === preview.primaryFormat)
    ?.standings.find((standing) => standing.rank === 1)
  const progress = preview.currentRound?.throughHole
    ? ` through ${preview.currentRound.throughHole}`
    : ''
  const title = preview.status === 'completed' || preview.status === 'archived'
    ? `${preview.tripName} — Final leaderboard`
    : `${preview.tripName} — Live leaderboard`
  const description = preview.moment?.summary
    ?? (leader
      ? `${leader.displayName} leads${progress}. Follow the standings on TeeCircle.`
      : 'Follow the live standings, hole by hole, on TeeCircle.')

  return { title, description }
}

function pageHtml(canonicalUrl: string, initial: InitialPreviewPayload): string {
  const meta = metadata(initial.preview, initial.pending)
  const title = htmlEscape(meta.title)
  const description = htmlEscape(meta.description)
  const url = htmlEscape(canonicalUrl)

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="robots" content="noindex,nofollow,noarchive" />
    <meta name="referrer" content="no-referrer" />
    <meta name="theme-color" content="#082b1e" />
    <meta name="description" content="${description}" />
    <meta property="og:type" content="website" />
    <meta property="og:site_name" content="TeeCircle" />
    <meta property="og:title" content="${title}" />
    <meta property="og:description" content="${description}" />
    <meta property="og:url" content="${url}" />
    <meta property="og:image" content="https://teecircle.vercel.app/icon-512.png" />
    <meta property="og:image:width" content="512" />
    <meta property="og:image:height" content="512" />
    <meta name="twitter:card" content="summary" />
    <meta name="twitter:title" content="${title}" />
    <meta name="twitter:description" content="${description}" />
    <meta name="apple-itunes-app" content="app-id=6757165880, app-argument=${url}" />
    <link rel="canonical" href="${url}" />
    <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png" />
    <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png" />
    <link rel="stylesheet" crossorigin href="/assets/app.css" />
    <title>${title}</title>
  </head>
  <body>
    <div id="root"></div>
    <script id="tee-circle-initial-preview" type="application/json">${safeJson(initial)}</script>
    <script type="module" crossorigin src="/assets/app.js"></script>
    <noscript>Open this link with JavaScript enabled to follow the TeeCircle leaderboard.</noscript>
  </body>
</html>`
}

export default async function handler(request: ApiRequest, response: ApiResponse) {
  response.setHeader('Content-Type', 'text/html; charset=utf-8')
  response.setHeader('Cache-Control', 'private, no-store, max-age=0')
  response.setHeader('X-Robots-Tag', 'noindex, nofollow, noarchive')
  response.setHeader('Referrer-Policy', 'no-referrer')
  response.setHeader('X-Content-Type-Options', 'nosniff')

  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return response.status(405).send('Method Not Allowed')
  }

  const rawToken = request.query.inviteToken
  const inviteToken = Array.isArray(rawToken) ? rawToken[0] : rawToken
  const safePathToken = validInviteToken(inviteToken) ? inviteToken : 'unavailable'
  // Use the deployed Vercel host until the custom domain is connected. Keeping
  // metadata and invite URLs on the same reachable host avoids dead previews.
  const canonicalUrl = `https://teecircle.vercel.app/t/${encodeURIComponent(safePathToken)}`

  if (!validInviteToken(inviteToken)) {
    return response.status(400).send(pageHtml(canonicalUrl, { error: 'unavailable' }))
  }

  const result = await fetchPublicPreview(inviteToken, {
    viewerIdentity: viewerIdentityFromVercelHeaders(request.headers),
  })
  const initial: InitialPreviewPayload = result.preview
    ? { preview: result.preview }
    : result.pending
      ? { pending: result.pending }
    : { error: result.error ?? 'unavailable' }

  // Keep the document itself available for expired or revoked links so people
  // receive a useful, branded state instead of a browser/server error page.
  return response.status(200).send(pageHtml(canonicalUrl, initial))
}
