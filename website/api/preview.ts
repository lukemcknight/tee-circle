import {
  fetchPublicPreview,
  validInviteToken,
  viewerIdentityFromVercelHeaders,
} from '../server/publicPreview.js'

interface ApiRequest {
  method?: string
  query: Record<string, string | string[] | undefined>
  headers: Record<string, string | string[] | undefined>
}

interface ApiResponse {
  status(code: number): ApiResponse
  setHeader(name: string, value: string): void
  json(body: unknown): void
}

export default async function handler(request: ApiRequest, response: ApiResponse) {
  response.setHeader('Cache-Control', 'private, no-store, max-age=0')
  response.setHeader('Referrer-Policy', 'no-referrer')

  if (request.method !== 'GET') {
    response.setHeader('Allow', 'GET')
    return response.status(405).json({ schemaVersion: 1, error: { code: 'method_not_allowed' } })
  }

  const rawToken = request.query.inviteToken
  const inviteToken = Array.isArray(rawToken) ? rawToken[0] : rawToken
  if (!validInviteToken(inviteToken)) {
    return response.status(400).json({ schemaVersion: 1, error: { code: 'invalid_invite' } })
  }

  const result = await fetchPublicPreview(inviteToken, {
    viewerIdentity: viewerIdentityFromVercelHeaders(request.headers),
  })
  if (result.pending) {
    return response.status(200).json({
      schemaVersion: 1,
      pending: result.pending,
    })
  }

  if (!result.preview) {
    return response.status(result.status).json({
      schemaVersion: 1,
      error: { code: `invite_${result.error ?? 'unavailable'}` },
    })
  }

  return response.status(200).json(result.preview)
}
