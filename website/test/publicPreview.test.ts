import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

import tripHandler from '../api/trip.ts'
import {
  fetchPublicPreview,
  PREVIEW_PROXY_SECRET_HEADER,
  PREVIEW_PROXY_VIEWER_HEADER,
  validInviteToken,
  viewerIdentityFromVercelHeaders,
} from '../server/publicPreview.ts'
import {
  parsePublicPending,
  parsePublicPreview,
  previewErrorKind,
} from '../src/liveTrip/publicPreview.ts'

const token = 'a'.repeat(64)

function edgePayload(displayName = 'Sean') {
  return {
    schemaVersion: 1,
    requestId: 'request-id',
    data: {
      trip: {
        publicId: 'public-trip',
        name: 'Pinehurst <Cup>',
        status: 'live',
        startsOn: '2026-07-13',
        endsOn: '2026-07-15',
        ownerId: 'must-not-leak',
        rounds: [{ publicId: 'round-public-id', holeCount: 9 }],
      },
      snapshot: {
        schemaVersion: 1,
        tripId: 'public-trip',
        revision: 42,
        status: 'live',
        primaryFormat: 'stableford',
        currentRound: {
          publicId: 'round-public-id',
          name: 'No. 2',
          throughHole: 12,
        },
        boards: [{
          format: 'stableford',
          scoring: 'net',
          standings: [{
            playerId: 'seat-id',
            displayName,
            rank: 1,
            value: 28,
            tied: false,
            holesPlayed: 12,
            email: 'private@example.com',
            handicap: 9.4,
            authId: 'private-auth-id',
          }],
        }],
        moment: { kind: 'lead_change', summary: 'Sean took the lead through 12' },
        generatedAt: '2026-07-13T18:00:00Z',
      },
    },
  }
}

function pendingEdgePayload() {
  return {
    schemaVersion: 1,
    requestId: 'request-id',
    data: {
      trip: {
        publicId: 'fresh-public-trip',
        name: 'Fresh Invite Cup',
        status: 'ready',
        startsOn: '2026-07-18',
        endsOn: '2026-07-19',
        ownerId: 'must-not-leak',
        ownerEmail: 'captain@example.com',
      },
      snapshot: null,
    },
  }
}

test('public parser allowlists fields and masks email-shaped names', () => {
  const preview = parsePublicPreview(edgePayload('private@example.com'))
  assert.ok(preview)
  assert.equal(preview.boards[0]?.standings[0]?.displayName, 'Player')
  assert.equal(preview.currentRound?.totalHoles, 9)
  const serialized = JSON.stringify(preview)
  assert.doesNotMatch(serialized, /private-auth-id|private@example\.com|handicap|ownerId/)
})

test('invite validation and revoked/expired states are stable', () => {
  assert.equal(validInviteToken(token), true)
  assert.equal(validInviteToken('a'.repeat(39)), false)
  assert.equal(validInviteToken('a'.repeat(129)), false)
  assert.equal(validInviteToken('../secret'), false)
  assert.equal(previewErrorKind({ error: { code: 'invite_revoked' } }, 401), 'revoked')
  assert.equal(previewErrorKind({ error: { code: 'invite_expired' } }, 401), 'expired')
  assert.equal(previewErrorKind({}, 503), 'offline')
})

test('Vercel viewer identity parsing accepts only a bounded network address', () => {
  assert.equal(viewerIdentityFromVercelHeaders({
    'x-vercel-forwarded-for': '203.0.113.9',
    'x-forwarded-for': '198.51.100.8',
  }), '203.0.113.9')
  assert.equal(viewerIdentityFromVercelHeaders({
    'x-forwarded-for': '2001:db8::8',
  }), '2001:db8::8')
  assert.equal(viewerIdentityFromVercelHeaders({
    'x-vercel-forwarded-for': 'not-an-address',
  }), undefined)
})

test('preview service forwards viewer identity only with the server proxy secret', async () => {
  const originalFetch = globalThis.fetch
  const originalEndpoint = process.env.PUBLIC_PREVIEW_ENDPOINT
  const originalSecret = process.env.PUBLIC_PREVIEW_PROXY_SECRET
  process.env.PUBLIC_PREVIEW_ENDPOINT = 'https://preview.invalid/function'
  process.env.PUBLIC_PREVIEW_PROXY_SECRET = 'server-only-proxy-secret'
  let outboundHeaders = new Headers()
  globalThis.fetch = (async (_input, init) => {
    outboundHeaders = new Headers(init?.headers)
    return new Response(JSON.stringify(pendingEdgePayload()), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  }) as typeof fetch

  try {
    const result = await fetchPublicPreview(token, { viewerIdentity: '203.0.113.9' })
    assert.equal(result.status, 200)
    assert.equal(outboundHeaders.get(PREVIEW_PROXY_SECRET_HEADER), 'server-only-proxy-secret')
    assert.equal(outboundHeaders.get(PREVIEW_PROXY_VIEWER_HEADER), '203.0.113.9')

    delete process.env.PUBLIC_PREVIEW_PROXY_SECRET
    await fetchPublicPreview(token, { viewerIdentity: '203.0.113.9' })
    assert.equal(outboundHeaders.has(PREVIEW_PROXY_SECRET_HEADER), false)
    assert.equal(outboundHeaders.has(PREVIEW_PROXY_VIEWER_HEADER), false)
  } finally {
    globalThis.fetch = originalFetch
    if (originalEndpoint === undefined) delete process.env.PUBLIC_PREVIEW_ENDPOINT
    else process.env.PUBLIC_PREVIEW_ENDPOINT = originalEndpoint
    if (originalSecret === undefined) delete process.env.PUBLIC_PREVIEW_PROXY_SECRET
    else process.env.PUBLIC_PREVIEW_PROXY_SECRET = originalSecret
  }
})

test('fresh invite parser returns a privacy-safe preparing state', () => {
  const pending = parsePublicPending(pendingEdgePayload())
  assert.deepEqual(pending, {
    schemaVersion: 1,
    state: 'preparing',
    tripId: 'fresh-public-trip',
    tripName: 'Fresh Invite Cup',
    status: 'ready',
    startsAt: '2026-07-18',
    endsAt: '2026-07-19',
  })
  assert.doesNotMatch(JSON.stringify(pending), /must-not-leak|captain@example\.com|ownerId/)
  assert.equal(parsePublicPreview(pendingEdgePayload()), null)
})

test('preview service preserves a valid snapshot-null response as HTTP 200 pending', async () => {
  const originalFetch = globalThis.fetch
  const originalEndpoint = process.env.PUBLIC_PREVIEW_ENDPOINT
  process.env.PUBLIC_PREVIEW_ENDPOINT = 'https://preview.invalid/function'
  globalThis.fetch = (async () => new Response(JSON.stringify(pendingEdgePayload()), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })) as typeof fetch

  try {
    const result = await fetchPublicPreview(token)
    assert.equal(result.status, 200)
    assert.equal(result.error, undefined)
    assert.equal(result.pending?.state, 'preparing')
    assert.equal(result.pending?.tripName, 'Fresh Invite Cup')
  } finally {
    globalThis.fetch = originalFetch
    if (originalEndpoint === undefined) delete process.env.PUBLIC_PREVIEW_ENDPOINT
    else process.env.PUBLIC_PREVIEW_ENDPOINT = originalEndpoint
  }
})

test('SSR emits escaped dynamic metadata, reachable canonical URLs, and noindex', async () => {
  const originalFetch = globalThis.fetch
  const originalEndpoint = process.env.PUBLIC_PREVIEW_ENDPOINT
  const originalSecret = process.env.PUBLIC_PREVIEW_PROXY_SECRET
  process.env.PUBLIC_PREVIEW_ENDPOINT = 'https://preview.invalid/function'
  process.env.PUBLIC_PREVIEW_PROXY_SECRET = 'server-only-proxy-secret'
  let outboundHeaders = new Headers()
  globalThis.fetch = (async (_input, init) => {
    outboundHeaders = new Headers(init?.headers)
    return new Response(JSON.stringify(edgePayload()), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  }) as typeof fetch

  const headers = new Map<string, string>()
  let status = 0
  let body = ''
  const response = {
    status(code: number) { status = code; return this },
    setHeader(name: string, value: string) { headers.set(name.toLowerCase(), value) },
    send(value: string) { body = value },
  }

  try {
    await tripHandler({
      method: 'GET',
      query: { inviteToken: token },
      headers: { 'x-vercel-forwarded-for': '203.0.113.12' },
    }, response)
  } finally {
    globalThis.fetch = originalFetch
    if (originalEndpoint === undefined) delete process.env.PUBLIC_PREVIEW_ENDPOINT
    else process.env.PUBLIC_PREVIEW_ENDPOINT = originalEndpoint
    if (originalSecret === undefined) delete process.env.PUBLIC_PREVIEW_PROXY_SECRET
    else process.env.PUBLIC_PREVIEW_PROXY_SECRET = originalSecret
  }

  assert.equal(status, 200)
  assert.equal(headers.get('x-robots-tag'), 'noindex, nofollow, noarchive')
  assert.equal(outboundHeaders.get(PREVIEW_PROXY_SECRET_HEADER), 'server-only-proxy-secret')
  assert.equal(outboundHeaders.get(PREVIEW_PROXY_VIEWER_HEADER), '203.0.113.12')
  assert.match(body, new RegExp(`https://teecircle\\.vercel\\.app/t/${token}`))
  assert.match(body, /https:\/\/teecircle\.vercel\.app\/icon-512\.png/)
  assert.doesNotMatch(body, /https:\/\/teecircle\.app\//)
  assert.match(body, /Pinehurst &lt;Cup&gt; — Live leaderboard/)
  assert.doesNotMatch(body, /must-not-leak|private-auth-id|private@example\.com/)
})

test('SSR renders fresh invites as preparing instead of an offline failure', async () => {
  const originalFetch = globalThis.fetch
  const originalEndpoint = process.env.PUBLIC_PREVIEW_ENDPOINT
  process.env.PUBLIC_PREVIEW_ENDPOINT = 'https://preview.invalid/function'
  globalThis.fetch = (async () => new Response(JSON.stringify(pendingEdgePayload()), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })) as typeof fetch

  let status = 0
  let body = ''
  const response = {
    status(code: number) { status = code; return this },
    setHeader(_name: string, _value: string) {},
    send(value: string) { body = value },
  }

  try {
    await tripHandler({ method: 'GET', query: { inviteToken: token }, headers: {} }, response)
  } finally {
    globalThis.fetch = originalFetch
    if (originalEndpoint === undefined) delete process.env.PUBLIC_PREVIEW_ENDPOINT
    else process.env.PUBLIC_PREVIEW_ENDPOINT = originalEndpoint
  }

  assert.equal(status, 200)
  assert.match(body, /Fresh Invite Cup — Leaderboard \| TeeCircle/)
  assert.match(body, /standings are being prepared/i)
  assert.match(body, /"state":"preparing"/)
  assert.doesNotMatch(body, /invite_offline|must-not-leak|captain@example\.com/)
})

test('AASA is valid JSON and associates only TeeCircle trip links', async () => {
  const url = new URL('../public/.well-known/apple-app-site-association', import.meta.url)
  const aasa = JSON.parse(await readFile(url, 'utf8'))
  assert.deepEqual(aasa.applinks.details, [{
    appIDs: ['9974PM5L6M.com.teecircle.app'],
    components: [{
      '/': '/t/*',
      comment: 'TeeCircle trip invitations and live leaderboards',
    }],
  }])
})
