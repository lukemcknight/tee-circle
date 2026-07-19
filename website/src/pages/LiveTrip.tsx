import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import {
  parsePublicPending,
  parsePublicPreview,
  previewErrorKind,
  type InitialPreviewPayload,
  type PublicBoard,
  type PublicPreviewErrorKind,
  type PublicTripPending,
  type PublicTripPreview,
} from '../liveTrip/publicPreview'
import styles from './LiveTrip.module.css'

const APP_STORE_URL = 'https://apps.apple.com/us/app/tee-circle-more-golf/id6757165880'
const POLL_INTERVAL_MS = 15_000

interface ViewState {
  preview?: PublicTripPreview
  pending?: PublicTripPending
  error?: PublicPreviewErrorKind
  refreshing: boolean
  stale: boolean
}

function readInitialPayload(): InitialPreviewPayload {
  const node = document.getElementById('tee-circle-initial-preview')
  if (!node?.textContent) return {}
  try {
    const value = JSON.parse(node.textContent) as InitialPreviewPayload
    const preview = value.preview ? parsePublicPreview(value.preview) : undefined
    const pending = value.pending ? parsePublicPending({ pending: value.pending }) : undefined
    return { preview: preview ?? undefined, pending: pending ?? undefined, error: value.error }
  } catch {
    return {}
  }
}

interface RequestedPreview {
  preview?: PublicTripPreview
  pending?: PublicTripPending
}

async function requestPreview(inviteToken: string, signal: AbortSignal): Promise<RequestedPreview> {
  const configuredEndpoint = import.meta.env.VITE_PUBLIC_PREVIEW_ENDPOINT as string | undefined
  const response = configuredEndpoint
    ? await fetch(configuredEndpoint, {
        method: 'POST',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
        body: JSON.stringify({ schemaVersion: 1, inviteToken }),
        cache: 'no-store',
        credentials: 'omit',
        signal,
      })
    : await fetch(`/api/preview?inviteToken=${encodeURIComponent(inviteToken)}`, {
        headers: { Accept: 'application/json' },
        cache: 'no-store',
        credentials: 'omit',
        signal,
      })

  let payload: unknown
  try {
    payload = await response.json()
  } catch {
    throw { kind: 'offline' satisfies PublicPreviewErrorKind }
  }

  if (!response.ok) {
    throw { kind: previewErrorKind(payload, response.status) }
  }

  const preview = parsePublicPreview(payload)
  if (preview) return { preview }

  const pending = parsePublicPending(payload)
  if (pending) return { pending }
  throw { kind: 'offline' satisfies PublicPreviewErrorKind }
}

function errorKind(value: unknown): PublicPreviewErrorKind {
  if (typeof value === 'object' && value !== null && 'kind' in value) {
    const kind = (value as { kind?: unknown }).kind
    if (kind === 'revoked' || kind === 'expired' || kind === 'unavailable' || kind === 'offline') {
      return kind
    }
  }
  return 'offline'
}

function useLivePreview(inviteToken: string) {
  const initial = useMemo(readInitialPayload, [])
  const [state, setState] = useState<ViewState>({
    preview: initial.preview,
    pending: initial.pending,
    error: initial.error,
    refreshing: !initial.preview && !initial.pending && !initial.error,
    stale: false,
  })
  const activeRequest = useRef<AbortController>()

  const refresh = useCallback(async (showSpinner = false) => {
    if (!inviteToken || activeRequest.current || document.visibilityState === 'hidden') return

    const controller = new AbortController()
    activeRequest.current = controller
    if (showSpinner) setState((current) => ({ ...current, refreshing: true }))

    try {
      const result = await requestPreview(inviteToken, controller.signal)
      setState({ ...result, refreshing: false, stale: false })
    } catch (error) {
      if (controller.signal.aborted) return
      const kind = errorKind(error)
      setState((current) => (current.preview || current.pending) && kind === 'offline'
        ? { ...current, error: kind, refreshing: false, stale: true }
        : { error: kind, refreshing: false, stale: false })
    } finally {
      if (activeRequest.current === controller) activeRequest.current = undefined
    }
  }, [inviteToken])

  useEffect(() => {
    if (!initial.preview && !initial.pending && !initial.error) void refresh(true)

    const timer = window.setInterval(() => void refresh(false), POLL_INTERVAL_MS)
    const handleVisibility = () => {
      if (document.visibilityState === 'visible') void refresh(false)
    }
    const handleOnline = () => void refresh(false)
    document.addEventListener('visibilitychange', handleVisibility)
    window.addEventListener('online', handleOnline)

    return () => {
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', handleVisibility)
      window.removeEventListener('online', handleOnline)
      activeRequest.current?.abort()
    }
  }, [initial.error, initial.pending, initial.preview, refresh])

  return { ...state, refresh: () => refresh(true) }
}

function setNamedMeta(name: string, content: string) {
  let meta = document.head.querySelector<HTMLMetaElement>(`meta[name="${name}"]`)
  if (!meta) {
    meta = document.createElement('meta')
    meta.name = name
    document.head.append(meta)
  }
  meta.content = content
}

function formatBoardName(board: PublicBoard): string {
  const format = board.format === 'stableford'
    ? 'Stableford'
    : board.format === 'skins'
      ? 'Skins'
      : 'Stroke play'
  return `${format} · ${board.scoring}`
}

function formatValue(board: PublicBoard, value: number | string): string {
  if (typeof value === 'string') return value
  if (board.format === 'stableford') return `${value} pts`
  if (board.format === 'skins') return `${value} ${value === 1 ? 'skin' : 'skins'}`
  if (value === 0) return 'E'
  return value > 0 ? `+${value}` : String(value)
}

function formatDateRange(preview: Pick<PublicTripPreview, 'startsAt' | 'endsAt'>): string | undefined {
  if (!preview.startsAt) return undefined
  const start = new Date(preview.startsAt)
  if (Number.isNaN(start.valueOf())) return undefined
  const end = preview.endsAt ? new Date(preview.endsAt) : undefined
  const date = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', year: 'numeric' })
  if (!end || Number.isNaN(end.valueOf()) || start.toDateString() === end.toDateString()) {
    return date.format(start)
  }
  const shortDate = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' })
  return `${shortDate.format(start)}–${date.format(end)}`
}

function syncLabel(generatedAt: string): string {
  const date = new Date(generatedAt)
  if (Number.isNaN(date.valueOf())) return 'Recently updated'
  return `Updated ${new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(date)}`
}

function statusCopy(status: PublicTripPreview['status']) {
  if (status === 'live') return { label: 'Live', eyebrow: 'On the course now' }
  if (status === 'ready') return { label: 'Upcoming', eyebrow: 'The first tee awaits' }
  return { label: 'Final', eyebrow: 'The clubhouse result' }
}

function LoadingState() {
  return (
    <div className={styles.stateCard} role="status" aria-live="polite">
      <div className={styles.loadingMark} aria-hidden="true"><span /><span /><span /></div>
      <p className={styles.stateKicker}>Walking to the scoreboard</p>
      <h1>Loading the live card…</h1>
      <p>We’re collecting the latest scores from the course.</p>
    </div>
  )
}

function PreparingState({ pending }: { pending: PublicTripPending }) {
  const dateRange = formatDateRange(pending)
  return (
    <div className={styles.stateCard} role="status" aria-live="polite">
      <div className={styles.loadingMark} aria-hidden="true"><span /><span /><span /></div>
      <p className={styles.stateKicker}>Scoreboard opening soon</p>
      <h1>Standings are being prepared.</h1>
      <p>
        {pending.tripName}{dateRange ? ` · ${dateRange}` : ''} is ready to share.
        Keep this page open and the first official leaderboard will appear automatically.
      </p>
    </div>
  )
}

const ERROR_CONTENT: Record<PublicPreviewErrorKind, { kicker: string; title: string; body: string }> = {
  revoked: {
    kicker: 'Link retired',
    title: 'This leaderboard is no longer being shared.',
    body: 'The trip captain closed this invitation. Ask them for a fresh TeeCircle link.',
  },
  expired: {
    kicker: 'Invitation expired',
    title: 'This gallery pass has expired.',
    body: 'Ask the trip captain to share a new link from TeeCircle.',
  },
  unavailable: {
    kicker: 'Card unavailable',
    title: 'We can’t find this leaderboard.',
    body: 'The link may be incomplete, or the trip may not be ready to share yet.',
  },
  offline: {
    kicker: 'Signal lost',
    title: 'The course is out of range.',
    body: 'The live card couldn’t reach TeeCircle. Check your connection and try again.',
  },
}

function ErrorState({ kind, onRetry }: { kind: PublicPreviewErrorKind; onRetry: () => void }) {
  const content = ERROR_CONTENT[kind]
  return (
    <div className={styles.stateCard} role="status">
      <div className={styles.flagMark} aria-hidden="true"><span /></div>
      <p className={styles.stateKicker}>{content.kicker}</p>
      <h1>{content.title}</h1>
      <p>{content.body}</p>
      {kind === 'offline' && (
        <button type="button" className={styles.retryButton} onClick={onRetry}>
          Try the scoreboard again
        </button>
      )}
    </div>
  )
}

function Leaderboard({ preview, stale }: { preview: PublicTripPreview; stale: boolean }) {
  const defaultKey = `${preview.primaryFormat}:${preview.boards.find((board) => board.format === preview.primaryFormat)?.scoring ?? 'gross'}`
  const [selectedKey, setSelectedKey] = useState(defaultKey)
  const selectedBoard = preview.boards.find((board) => `${board.format}:${board.scoring}` === selectedKey)
    ?? preview.boards.find((board) => board.format === preview.primaryFormat)
    ?? preview.boards[0]
  const copy = statusCopy(preview.status)
  const dateRange = formatDateRange(preview)
  const round = preview.currentRound

  useEffect(() => {
    if (!preview.boards.some((board) => `${board.format}:${board.scoring}` === selectedKey)) {
      setSelectedKey(defaultKey)
    }
  }, [defaultKey, preview.boards, selectedKey])

  return (
    <>
      {stale && (
        <div className={styles.staleBanner} role="status">
          <span aria-hidden="true" /> Live signal interrupted. Showing the last complete update.
        </div>
      )}

      <section className={styles.eventIntro} aria-labelledby="trip-title">
        <div className={styles.eventCopy}>
          <div className={styles.statusLine}>
            <span className={`${styles.liveDot} ${preview.status === 'live' ? styles.isLive : ''}`} aria-hidden="true" />
            <span>{copy.label}</span>
            <span className={styles.statusDivider} aria-hidden="true" />
            <span>{copy.eyebrow}</span>
          </div>
          <h1 id="trip-title">{preview.tripName}</h1>
          <div className={styles.eventMeta}>
            {dateRange && <span>{dateRange}</span>}
            {round && <span>{round.name}</span>}
          </div>
        </div>

        <div className={styles.progressStamp} aria-label={round ? `Through hole ${round.throughHole} of ${round.totalHoles}` : 'Tournament card'}>
          <span>{preview.status === 'completed' || preview.status === 'archived' ? 'Final' : 'Through'}</span>
          <strong>{round?.throughHole ?? '—'}</strong>
          <small>{round ? `of ${round.totalHoles}` : 'TeeCircle'}</small>
        </div>
      </section>

      {preview.moment && (
        <aside className={styles.moment} aria-label="Latest tournament update">
          <span className={styles.momentLabel}>From the course</span>
          <p>{preview.moment.summary}</p>
          <span className={styles.momentArrow} aria-hidden="true">↗</span>
        </aside>
      )}

      <section className={styles.boardCard} aria-labelledby="leaderboard-title">
        <div className={styles.boardHeader}>
          <div>
            <p className={styles.boardOverline}>Official card · Revision {preview.revision}</p>
            <h2 id="leaderboard-title">Leaderboard</h2>
          </div>
          <span className={styles.syncTime}>{syncLabel(preview.generatedAt)}</span>
        </div>

        {preview.boards.length > 1 && (
          <div className={styles.boardTabs} role="tablist" aria-label="Leaderboards">
            {preview.boards.map((board) => {
              const key = `${board.format}:${board.scoring}`
              return (
                <button
                  key={key}
                  type="button"
                  role="tab"
                  aria-selected={selectedKey === key}
                  className={selectedKey === key ? styles.activeTab : undefined}
                  onClick={() => setSelectedKey(key)}
                >
                  {formatBoardName(board)}
                </button>
              )
            })}
          </div>
        )}

        {selectedBoard && selectedBoard.standings.length > 0 ? (
          <div className={styles.tableScroll}>
            <table className={styles.leaderboardTable}>
              <caption className="srOnly">{formatBoardName(selectedBoard)} standings</caption>
              <thead>
                <tr>
                  <th scope="col">Pos</th>
                  <th scope="col">Player</th>
                  <th scope="col">Thru</th>
                  <th scope="col">Score</th>
                </tr>
              </thead>
              <tbody>
                {selectedBoard.standings.map((standing, index) => (
                  <tr key={`${standing.playerId}-${index}`} className={standing.rank === 1 ? styles.leaderRow : undefined}>
                    <td className={styles.rankCell}>
                      <span>{standing.tied ? 'T' : ''}{standing.rank}</span>
                    </td>
                    <th scope="row">
                      <span className={styles.playerName}>{standing.displayName}</span>
                      {standing.rank === 1 && <span className={styles.leaderTag}>Leader</span>}
                    </th>
                    <td className={styles.throughCell}>{standing.holesPlayed || '—'}</td>
                    <td className={styles.valueCell}>{formatValue(selectedBoard, standing.value)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className={styles.emptyBoard}>
            <span aria-hidden="true">01</span>
            <p>The card is set. Scores will appear after the opening hole.</p>
          </div>
        )}

        <div className={styles.boardFooter}>
          <span>Scores supplied by the players</span>
          <span>{selectedBoard ? formatBoardName(selectedBoard) : 'Official standings'}</span>
        </div>
      </section>

      <aside className={styles.appCallout}>
        <div>
          <p className={styles.appEyebrow}>Want the whole round?</p>
          <h2>Score, share, and follow from TeeCircle.</h2>
        </div>
        <a href={APP_STORE_URL}>Get the iPhone app <span aria-hidden="true">↗</span></a>
      </aside>
    </>
  )
}

export function LiveTrip() {
  const { inviteToken = '' } = useParams()
  const { preview, pending, error, refreshing, stale, refresh } = useLivePreview(inviteToken)

  useEffect(() => {
    setNamedMeta('robots', 'noindex,nofollow,noarchive')
    setNamedMeta('referrer', 'no-referrer')
    setNamedMeta('theme-color', '#082b1e')
    document.title = preview
      ? `${preview.tripName} — ${preview.status === 'live' ? 'Live' : 'Leaderboard'} | TeeCircle`
      : pending
        ? `${pending.tripName} — Leaderboard | TeeCircle`
        : 'Live leaderboard | TeeCircle'
  }, [pending, preview])

  return (
    <div className={styles.livePage}>
      <a className={styles.skipLink} href="#live-board">Skip to leaderboard</a>
      <header className={styles.masthead}>
        <Link to="/" className={styles.wordmark} aria-label="TeeCircle home">
          <img src="/favicon.png" alt="" />
          <span>TeeCircle</span>
        </Link>
        <div className={styles.broadcastLabel}>
          <span aria-hidden="true" /> Live tournament card
        </div>
      </header>

      <main id="live-board" className={styles.main} tabIndex={-1}>
        {preview
          ? <Leaderboard preview={preview} stale={stale} />
          : pending
            ? <PreparingState pending={pending} />
          : refreshing
            ? <LoadingState />
            : <ErrorState kind={error ?? 'unavailable'} onRetry={refresh} />}
      </main>

      <footer className={styles.liveFooter}>
        <p>Golf moves quickly. This card updates while it’s open.</p>
        <nav aria-label="Legal">
          <Link to="/privacy">Privacy</Link>
          <Link to="/terms">Terms</Link>
          <a href="mailto:support@teecircle.app">Support</a>
        </nav>
      </footer>
      <div className="srOnly" aria-live="polite">
        {preview
          ? `Leaderboard revision ${preview.revision} loaded`
          : pending
            ? 'Standings are being prepared and will refresh automatically'
            : ''}
      </div>
    </div>
  )
}
