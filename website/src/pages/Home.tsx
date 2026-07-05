import styles from './Home.module.css'

export function Home() {
  return (
    <div className={styles.page}>
      <section className={styles.hero}>
        <div className={styles.heroContent}>
          <img src="/favicon.png" alt="TeeCircle" className={styles.heroLogo} />
          <h1 className={styles.title}>Golf is better<br />with friends</h1>
          <p className={styles.subtitle}>
            Organize rounds, invite friends, and track RSVPs — all in one place.
          </p>
          <div className={styles.buttons}>
            <a href="https://apps.apple.com/us/app/tee-circle-more-golf/id6757165880" className={styles.primaryButton}>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
              </svg>
              Download on the App Store
            </a>
          </div>
        </div>
      </section>

      <section className={styles.features}>
        <div className={styles.sectionHeader}>
          <h2 className={styles.sectionTitle}>Everything you need for your next round</h2>
          <p className={styles.sectionSubtitle}>Simple tools that keep your golf group organized.</p>
        </div>
        <div className={styles.featureGrid}>
          <div className={styles.feature}>
            <div className={styles.featureIconWrapper}>
              <img src="/calendar-tee-circle.png" alt="" className={styles.featureImage} />
            </div>
            <h3>Create Rounds</h3>
            <p>Set up a round with course, date, time, and format. It takes seconds.</p>
          </div>
          <div className={styles.feature}>
            <div className={styles.featureIconWrapper}>
              <img src="/friends-tee-circle.png" alt="" className={styles.featureImage} />
            </div>
            <h3>Invite Friends</h3>
            <p>Add your golf buddies and invite them to join your rounds.</p>
          </div>
          <div className={styles.feature}>
            <div className={styles.featureIconWrapper}>
              <svg className={styles.featureSvg} viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
                <rect width="64" height="64" rx="14" fill="#4A7C59" />
                <path d="M18 33L27 42L46 22" stroke="white" strokeWidth="5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </div>
            <h3>Track RSVPs</h3>
            <p>See who's in, who's out, and who's still deciding at a glance.</p>
          </div>
        </div>
      </section>

      <section className={styles.cta}>
        <div className={styles.ctaContent}>
          <h2>Ready to hit the links?</h2>
          <p>Download TeeCircle and start organizing your next round today.</p>
          <a href="#" className={styles.ctaButton}>
            Get the App
          </a>
        </div>
      </section>
    </div>
  )
}
