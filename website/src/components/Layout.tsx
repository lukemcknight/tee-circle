import { Outlet, Link } from 'react-router-dom'
import styles from './Layout.module.css'

const APP_STORE_URL = 'https://apps.apple.com/us/app/tee-circle-more-golf/id6757165880'

export function Layout() {
  return (
    <div className={styles.container}>
      <header className={styles.header}>
        <Link to="/" className={styles.logo} aria-label="TeeCircle home">
          <img src="/favicon.png" alt="" className={styles.logoIcon} />
          <span>TeeCircle</span>
        </Link>
        <nav className={styles.nav} aria-label="Main navigation">
          <a href="/#how-it-works">How it works</a>
          <a href="/#messages">Messages</a>
          <a href={APP_STORE_URL} className={styles.navCta}>Get the app <span>↗</span></a>
        </nav>
      </header>
      <main className={styles.main}>
        <Outlet />
      </main>
      <footer className={styles.footer}>
        <div className={styles.footerContent}>
          <Link to="/" className={styles.footerBrand} aria-label="TeeCircle home">
            <img src="/favicon.png" alt="" />
            <span><strong>TeeCircle</strong><small>Golf plans, made real.</small></span>
          </Link>
          <p>&copy; {new Date().getFullYear()} Luke McKnight. All rights reserved.</p>
          <div className={styles.footerLinks}>
            <Link to="/privacy">Privacy</Link>
            <Link to="/terms">Terms</Link>
            <a href="mailto:support@teecircle.app">Contact</a>
          </div>
        </div>
      </footer>
    </div>
  )
}
