export type TripStatus = 'ready' | 'live' | 'completed' | 'archived'

export type BoardFormat = 'stableford' | 'skins' | 'stroke_play'
export type ScoringMode = 'gross' | 'net'

export interface PublicStanding {
  playerId: string
  displayName: string
  rank: number
  value: number | string
  tied: boolean
  holesPlayed: number
}

export interface PublicBoard {
  format: BoardFormat
  scoring: ScoringMode
  standings: PublicStanding[]
}

export interface PublicRound {
  publicId: string
  name: string
  throughHole: number
  totalHoles: number
}

export interface PublicMoment {
  kind: string
  summary: string
}

export interface PublicTripPreview {
  schemaVersion: 1
  tripId: string
  tripName: string
  status: TripStatus
  revision: number
  primaryFormat: BoardFormat
  startsAt?: string
  endsAt?: string
  currentRound?: PublicRound
  boards: PublicBoard[]
  moment?: PublicMoment
  generatedAt: string
}

export interface PublicTripPending {
  schemaVersion: 1
  state: 'preparing'
  tripId: string
  tripName: string
  status: TripStatus
  startsAt?: string
  endsAt?: string
}

export type PublicPreviewErrorKind =
  | 'revoked'
  | 'expired'
  | 'unavailable'
  | 'offline'

export interface InitialPreviewPayload {
  preview?: PublicTripPreview
  pending?: PublicTripPending
  error?: PublicPreviewErrorKind
}

type JsonRecord = Record<string, unknown>

const MAX_NAME_LENGTH = 80
const MAX_SUMMARY_LENGTH = 180
const MAX_STANDINGS = 80

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function recordAt(value: unknown, key: string): JsonRecord | undefined {
  if (!isRecord(value)) return undefined
  const child = value[key]
  return isRecord(child) ? child : undefined
}

function cleanString(value: unknown, maxLength: number): string | undefined {
  if (typeof value !== 'string') return undefined
  const cleaned = value.replace(/[\u0000-\u001f\u007f]/g, '').trim()
  if (!cleaned) return undefined
  return cleaned.slice(0, maxLength)
}

function cleanDisplayName(value: unknown): string {
  const name = cleanString(value, 40)
  // A public preview should never contain email addresses. Mask one if an
  // upstream contract regresses instead of rendering it into a shared page.
  if (!name || name.includes('@')) return 'Player'
  return name
}

function finiteNumber(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined
}

function nonNegativeInteger(value: unknown, fallback = 0): number {
  const number = finiteNumber(value)
  return number === undefined ? fallback : Math.max(0, Math.floor(number))
}

function parseStatus(value: unknown): TripStatus | undefined {
  return value === 'ready' || value === 'live' || value === 'completed' || value === 'archived'
    ? value
    : undefined
}

function parseFormat(value: unknown): BoardFormat | undefined {
  if (value === 'stableford' || value === 'skins' || value === 'stroke_play') return value
  return undefined
}

function parseScoring(value: unknown): ScoringMode {
  return value === 'net' ? 'net' : 'gross'
}

function parseValue(value: unknown): number | string {
  const number = finiteNumber(value)
  if (number !== undefined) return number
  return cleanString(value, 16) ?? '—'
}

function parseBoards(value: unknown): PublicBoard[] {
  if (!Array.isArray(value)) return []

  return value.flatMap((candidate): PublicBoard[] => {
    if (!isRecord(candidate)) return []
    const format = parseFormat(candidate.format)
    if (!format || !Array.isArray(candidate.standings)) return []

    const standings = candidate.standings
      .slice(0, MAX_STANDINGS)
      .flatMap((standing, index): PublicStanding[] => {
        if (!isRecord(standing)) return []
        const rank = nonNegativeInteger(standing.rank, index + 1)
        return [{
          playerId: cleanString(standing.playerId, 80) ?? `standing-${index + 1}`,
          displayName: cleanDisplayName(standing.displayName),
          rank: rank || index + 1,
          value: parseValue(standing.value),
          tied: standing.tied === true,
          holesPlayed: nonNegativeInteger(standing.holesPlayed),
        }]
      })

    return [{ format, scoring: parseScoring(candidate.scoring), standings }]
  })
}

function unwrapPayload(payload: unknown): { source: JsonRecord; trip?: JsonRecord; snapshot: JsonRecord } | null {
  if (!isRecord(payload)) return null
  const source = recordAt(payload, 'preview') ?? recordAt(payload, 'data') ?? payload
  const trip = recordAt(source, 'trip') ?? recordAt(payload, 'trip')
  const snapshot = recordAt(source, 'snapshot') ?? recordAt(source, 'latestSnapshot') ?? source
  return { source, trip, snapshot }
}

function unwrapPendingPayload(payload: unknown): { source: JsonRecord; trip: JsonRecord } | null {
  if (!isRecord(payload)) return null
  const prepared = recordAt(payload, 'pending')
  if (prepared?.state === 'preparing') return { source: prepared, trip: prepared }

  const source = recordAt(payload, 'preview') ?? recordAt(payload, 'data') ?? payload
  const trip = recordAt(source, 'trip') ?? recordAt(payload, 'trip')
  const hasPendingSnapshot = (
    Object.prototype.hasOwnProperty.call(source, 'snapshot') && source.snapshot === null
  ) || (
    Object.prototype.hasOwnProperty.call(source, 'latestSnapshot') && source.latestSnapshot === null
  )
  return trip && hasPendingSnapshot ? { source, trip } : null
}

/**
 * Parses the deliberately small state returned for a valid invitation whose
 * first authoritative leaderboard snapshot has not been generated yet.
 */
export function parsePublicPending(payload: unknown): PublicTripPending | null {
  const unwrapped = unwrapPendingPayload(payload)
  if (!unwrapped) return null

  const { source, trip } = unwrapped
  const status = parseStatus(trip.status ?? source.status)
  const tripName = cleanString(trip.name ?? source.tripName, MAX_NAME_LENGTH)
  const tripId = cleanString(trip.publicId ?? source.tripId, 100)
  if (!status || !tripName || !tripId) return null

  const dateRange = recordAt(trip, 'dateRange') ?? recordAt(source, 'dateRange')
  return {
    schemaVersion: 1,
    state: 'preparing',
    tripId,
    tripName,
    status,
    startsAt: cleanString(
      trip.startsAt ?? trip.startsOn ?? trip.startDate ?? source.startsAt ?? source.startsOn
        ?? dateRange?.startsAt ?? dateRange?.start,
      40,
    ),
    endsAt: cleanString(
      trip.endsAt ?? trip.endsOn ?? trip.endDate ?? source.endsAt ?? source.endsOn
        ?? dateRange?.endsAt ?? dateRange?.end,
      40,
    ),
  }
}

/**
 * Converts an Edge Function response into the intentionally narrow public DTO.
 * Unknown properties are dropped so auth identifiers, emails, handicaps, and
 * other private fields can never be proxied by the website accidentally.
 */
export function parsePublicPreview(payload: unknown): PublicTripPreview | null {
  const unwrapped = unwrapPayload(payload)
  if (!unwrapped) return null

  const { source, trip, snapshot } = unwrapped
  const status = parseStatus(snapshot.status ?? trip?.status ?? source.status)
  const boards = parseBoards(snapshot.boards)
  const primaryFormat = parseFormat(snapshot.primaryFormat) ?? boards[0]?.format
  const tripName = cleanString(
    trip?.name ?? source.tripName ?? snapshot.tripName,
    MAX_NAME_LENGTH,
  )
  const tripId = cleanString(
    snapshot.tripId ?? trip?.publicId ?? source.tripId,
    100,
  )
  const generatedAt = cleanString(snapshot.generatedAt, 40)

  if (!status || !primaryFormat || !tripName || !tripId || !generatedAt) return null

  const currentRoundRecord = recordAt(snapshot, 'currentRound')
  const roundName = cleanString(currentRoundRecord?.name, MAX_NAME_LENGTH)
  const currentRoundPublicId = cleanString(currentRoundRecord?.publicId, 100)
  const matchingTripRound = Array.isArray(trip?.rounds)
    ? trip.rounds.find((round) => (
        isRecord(round)
        && currentRoundPublicId !== undefined
        && cleanString(round.publicId, 100) === currentRoundPublicId
      ))
    : undefined
  const throughHole = nonNegativeInteger(currentRoundRecord?.throughHole)
  const currentRound = currentRoundRecord && roundName
    ? {
        publicId: currentRoundPublicId ?? 'current-round',
        name: roundName,
        throughHole,
        totalHoles: Math.max(
          1,
          nonNegativeInteger(
            currentRoundRecord.totalHoles
              ?? (isRecord(matchingTripRound) ? matchingTripRound.holeCount : undefined),
            throughHole || 1,
          ),
        ),
      }
    : undefined

  const momentRecord = recordAt(snapshot, 'moment')
  const momentSummary = cleanString(momentRecord?.summary, MAX_SUMMARY_LENGTH)
  const moment = momentRecord && momentSummary
    ? {
        kind: cleanString(momentRecord.kind, 40) ?? 'update',
        summary: momentSummary,
      }
    : undefined

  const dateRange = recordAt(trip, 'dateRange') ?? recordAt(source, 'dateRange')

  return {
    schemaVersion: 1,
    tripId,
    tripName,
    status,
    revision: nonNegativeInteger(snapshot.revision),
    primaryFormat,
    startsAt: cleanString(
      trip?.startsAt ?? trip?.startsOn ?? trip?.startDate ?? source.startsAt ?? source.startsOn
        ?? dateRange?.startsAt ?? dateRange?.start,
      40,
    ),
    endsAt: cleanString(
      trip?.endsAt ?? trip?.endsOn ?? trip?.endDate ?? source.endsAt ?? source.endsOn
        ?? dateRange?.endsAt ?? dateRange?.end,
      40,
    ),
    currentRound,
    boards,
    moment,
    generatedAt,
  }
}

export function previewErrorKind(payload: unknown, status: number): PublicPreviewErrorKind {
  const root = isRecord(payload) ? payload : undefined
  const error = recordAt(root, 'error')
  const code = cleanString(error?.code ?? root?.code, 80)?.toLowerCase() ?? ''

  if (code.includes('revok')) return 'revoked'
  if (code.includes('expir')) return 'expired'
  if (status === 410) return 'revoked'
  if (status === 404) return 'unavailable'
  return status >= 500 || status === 429 ? 'offline' : 'unavailable'
}
