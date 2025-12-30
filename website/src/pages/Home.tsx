import styles from './Home.module.css'

export function Home() {
  return (
    <div className={styles.container}>
      <section className={styles.hero}>
        <h1 className={styles.title}>Golf is better with friends</h1>
        <p className={styles.subtitle}>
          Organize rounds, invite friends, and track RSVPs — all in one place.
        </p>
        <div className={styles.buttons}>
          <a href="#" className={styles.primaryButton}>
            Download on the App Store
          </a>
        </div>
      </section>

      <section className={styles.features}>
        <div className={styles.feature}>
          <div className={styles.featureIcon}>&#9971;</div>
          <h3>Create Rounds</h3>
          <p>Set up a round with course, date, time, and format. It takes seconds.</p>
        </div>
        <div className={styles.feature}>
          <div className={styles.featureIcon}>&#128101;</div>
          <h3>Invite Friends</h3>
          <p>Add your golf buddies and invite them to join your rounds.</p>
        </div>
        <div className={styles.feature}>
          <div className={styles.featureIcon}>&#9989;</div>
          <h3>Track RSVPs</h3>
          <p>See who's in, who's out, and who's still deciding at a glance.</p>
        </div>
      </section>

      <section className={styles.cta}>
        <h2>Ready to hit the links?</h2>
        <p>Download TeeCircle and start organizing your next round.</p>
        <a href="#" className={styles.primaryButton}>
          Get the App
        </a>
      </section>
    </div>
  )
}
