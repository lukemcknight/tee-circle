import styles from './Home.module.css'

const APP_STORE_URL = 'https://apps.apple.com/us/app/tee-circle-more-golf/id6757165880'

function AppleMark() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" className={styles.appleMark}>
      <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
    </svg>
  )
}

function ArrowMark() {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" className={styles.arrowMark}>
      <path d="M4 10h11M11 5.5 15.5 10 11 14.5" />
    </svg>
  )
}

function AppStoreButton({ className = '' }: { className?: string }) {
  return (
    <a
      href={APP_STORE_URL}
      className={`${styles.appStoreButton} ${className}`.trim()}
      aria-label="Download TeeCircle on the App Store"
    >
      <AppleMark />
      <span>
        <small>Download on the</small>
        <strong>App Store</strong>
      </span>
    </a>
  )
}

export function Home() {
  return (
    <div className={styles.page}>
      <section className={styles.hero} aria-labelledby="hero-title">
        <div className={styles.heroGlow} aria-hidden="true" />
        <div className={styles.heroInner}>
          <div className={styles.heroCopy}>
            <p className={styles.eyebrow}>
              <span>Now on the App Store</span>
              Round scheduling for golf crews
            </p>
            <h1 id="hero-title" className={styles.title}>
              Make the tee time.
              <span>Send it to the group chat.</span>
              Know who&rsquo;s in.
            </h1>
            <p className={styles.heroText}>
              TeeCircle turns &ldquo;we should play&rdquo; into an actual round. Pick the course,
              set the time, invite your people, and stop chasing replies.
            </p>

            <div className={styles.heroActions}>
              <AppStoreButton />
              <a href="#how-it-works" className={styles.textButton}>
                See the round flow
                <ArrowMark />
              </a>
            </div>

            <div className={styles.releaseNotes} aria-label="TeeCircle feature availability">
              <p>
                <span className={styles.liveDot} aria-hidden="true" />
                <strong>Available now</strong>
                Round creation &amp; in-app RSVPs
              </p>
              <p>
                <span className={styles.buildDot} aria-hidden="true" />
                <strong>In the build</strong>
                Messages sharing
              </p>
            </div>
          </div>

          <div className={styles.heroVisual} aria-hidden="true">
            <div className={styles.dateTicket}>
              <span>Sat</span>
              <strong>24</strong>
              <span>Aug</span>
              <small>Round 01</small>
            </div>

            <div className={styles.chatPeek}>
              <span>Golf Group</span>
              <p>Who&rsquo;s around Saturday?</p>
            </div>

            <div className={styles.creatorCard}>
              <div className={styles.creatorTopbar}>
                <span>Cancel</span>
                <strong>New Tee Time</strong>
                <span>Save</span>
              </div>

              <div className={styles.creatorBody}>
                <div className={styles.creatorIntro}>
                  <p>Course details</p>
                  <span>01 / 03</span>
                </div>

                <div className={styles.field}>
                  <small>Location</small>
                  <div>
                    <svg viewBox="0 0 20 20"><path d="M10 18s5-4.8 5-10a5 5 0 1 0-10 0c0 5.2 5 10 5 10Z"/><circle cx="10" cy="8" r="1.8"/></svg>
                    <span>Pine Hills Golf Club</span>
                    <b>⌄</b>
                  </div>
                </div>

                <div className={styles.fieldRow}>
                  <div className={styles.field}>
                    <small>Date</small>
                    <div>
                      <span>Sat, Aug 24</span>
                      <svg viewBox="0 0 20 20"><rect x="3" y="4.5" width="14" height="12" rx="2"/><path d="M6.5 2.8v3.4M13.5 2.8v3.4M3 8.2h14"/></svg>
                    </div>
                  </div>
                  <div className={styles.field}>
                    <small>Time</small>
                    <div>
                      <span>8:10 AM</span>
                      <svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="7"/><path d="M10 6v4.2l2.8 1.7"/></svg>
                    </div>
                  </div>
                </div>

                <div className={styles.formatRow}>
                  <p>
                    <small>Length</small>
                    <strong>18 holes</strong>
                  </p>
                  <span />
                  <p>
                    <small>Getting around</small>
                    <strong>Walking</strong>
                  </p>
                </div>

                <div className={styles.playersHeader}>
                  <p>Who&rsquo;s playing?</p>
                  <span>3 in · 1 pending</span>
                </div>
                <div className={styles.playerRow}>
                  <div className={styles.avatars}>
                    <span>LM</span><span>JD</span><span>MK</span><span>+</span>
                  </div>
                  <div className={styles.confirmedPill}>
                    <i /> Confirmed
                  </div>
                </div>

                <div className={styles.createAction}>
                  Create &amp; send invites
                  <svg viewBox="0 0 20 20"><path d="m3 9 14-6-5.3 14-2.3-5.1L3 9Z"/><path d="m9.4 11.9 3-3"/></svg>
                </div>
              </div>
            </div>

            <div className={styles.scoreStrip}>
              <span>Course</span><strong>PHGC</strong>
              <span>Players</span><strong>4</strong>
              <span>Tee</span><strong>08:10</strong>
            </div>
          </div>
          <p className="srOnly">
            A preview of TeeCircle&rsquo;s New Tee Time screen with Pine Hills Golf Club,
            Saturday August 24 at 8:10 AM, and three confirmed players.
          </p>
        </div>
      </section>

      <section className={styles.promiseBar} aria-label="TeeCircle round workflow summary">
        <div>
          <span>01</span><p><strong>Make it</strong>Course, date, time</p>
        </div>
        <div>
          <span>02</span><p><strong>Send it</strong>Your usual golf crew</p>
        </div>
        <div>
          <span>03</span><p><strong>Fill it</strong>Yes, no, or still deciding</p>
        </div>
      </section>

      <section id="how-it-works" className={styles.roundSection} aria-labelledby="round-title">
        <div className={styles.sectionHeading}>
          <p className={styles.sectionLabel}>The everyday round</p>
          <h2 id="round-title">Your foursome, without the follow-ups.</h2>
          <p>
            The round creator is the heart of TeeCircle: everything the group needs,
            and none of the tournament-admin energy when you&rsquo;re just trying to play Saturday.
          </p>
        </div>

        <div className={styles.stepGrid}>
          <article className={styles.stepCard}>
            <div className={styles.stepNumber}>01</div>
            <div className={styles.miniCalendar} aria-hidden="true">
              <span>August</span>
              <b>24</b>
              <small>Saturday · 8:10</small>
            </div>
            <h3>Set the round</h3>
            <p>Choose the course, date, tee time, holes, and how you&rsquo;re getting around.</p>
          </article>

          <article className={styles.stepCard}>
            <div className={styles.stepNumber}>02</div>
            <div className={styles.inviteGlyph} aria-hidden="true">
              <span>TC</span>
              <div>
                <b>Saturday at 8:10?</b>
                <small>Pine Hills · 18 holes</small>
              </div>
              <i>↗</i>
            </div>
            <h3>Invite the crew</h3>
            <p>Bring the people you actually play with into one round instead of another loose plan.</p>
          </article>

          <article className={styles.stepCard}>
            <div className={styles.stepNumber}>03</div>
            <div className={styles.rsvpGlyph} aria-hidden="true">
              <div><span>JD</span><p><b>Jake</b><small>Confirmed</small></p><i>✓</i></div>
              <div><span>MK</span><p><b>Mike</b><small>Waiting</small></p><i>···</i></div>
            </div>
            <h3>Know who&rsquo;s in</h3>
            <p>See confirmations and pending replies at a glance, while there&rsquo;s still time to find a fourth.</p>
          </article>
        </div>
      </section>

      <section id="messages" className={styles.messagesSection} aria-labelledby="messages-title">
        <div className={styles.messagesVisual} aria-hidden="true">
          <div className={styles.messageTopbar}>
            <div className={styles.messageAvatar}>19</div>
            <p><strong>Saturday Golf</strong><span>4 people ›</span></p>
          </div>
          <div className={styles.incomingBubble}>Anybody want the 8:10 Saturday?</div>
          <div className={styles.outgoingBubble}>Yep — I made the round.</div>
          <div className={styles.messageInvite}>
            <div className={styles.messageInviteHeader}>
              <img src="/favicon.png" alt="" />
              <span>TeeCircle</span>
              <small>Round invite</small>
            </div>
            <div className={styles.messageInviteBody}>
              <div><span>Aug</span><strong>24</strong></div>
              <p><strong>Pine Hills Golf Club</strong><span>Saturday · 8:10 AM · 18 holes</span></p>
            </div>
            <div className={styles.messageInviteFooter}>View round <span>→</span></div>
          </div>
          <p className={styles.delivered}>Delivered</p>
        </div>

        <div className={styles.messagesCopy}>
          <p className={styles.sectionLabel}>Next up · Messages</p>
          <h2 id="messages-title">The invite belongs where the plan starts.</h2>
          <p>
            A TeeCircle Messages extension is already built and being prepared for public release.
            The App Store version today keeps invitations and replies inside TeeCircle; the extension
            is the next step toward dropping the same live round card into the group chat.
          </p>
          <div className={styles.buildStatus}>
            <span className={styles.buildDot} aria-hidden="true" />
            <strong>Extension built</strong>
            <span>Public release ahead</span>
          </div>
        </div>
      </section>

      <section className={styles.roadmapSection} aria-labelledby="roadmap-title">
        <div className={styles.roadmapNumber} aria-hidden="true">BACK 9</div>
        <div className={styles.roadmapCopy}>
          <p className={styles.sectionLabel}>On the horizon</p>
          <h2 id="roadmap-title">Rounds now. Golf weekends next.</h2>
          <p>
            We&rsquo;re keeping the everyday tee time front and center while multi-round trip planning
            and competition tools take shape in the background.
          </p>
        </div>
        <div className={styles.roadmapList} aria-label="TeeCircle roadmap features">
          <p><span>01</span>Multi-round weekends<small>Roadmap</small></p>
          <p><span>02</span>One shared trip roster<small>Roadmap</small></p>
          <p><span>03</span>Live competition cards<small>Roadmap</small></p>
        </div>
      </section>

      <section className={styles.finalCta} aria-labelledby="cta-title">
        <div className={styles.ctaFlag} aria-hidden="true">
          <span />
          <i />
        </div>
        <p className={styles.sectionLabel}>Your move, captain</p>
        <h2 id="cta-title">Put a real round on the calendar.</h2>
        <p>Make the tee time. TeeCircle will help you fill it.</p>
        <AppStoreButton className={styles.ctaButton} />
      </section>
    </div>
  )
}
