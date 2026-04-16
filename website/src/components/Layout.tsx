import { Outlet, Link } from 'react-router-dom'
import styles from './Layout.module.css'

export function Layout() {
  return (
    <div className={styles.container}>
      <header className={styles.header}>
        <Link to="/" className={styles.logo}>
          <img src="/favicon.png" alt="TeeCircle" className={styles.logoIcon} />
          TeeCircle
        </Link>
        <nav className={styles.nav}>
          <Link to="/privacy">Privacy</Link>
          <Link to="/terms">Terms</Link>
        </nav>
      </header>
      <main className={styles.main}>
        <Outlet />
      </main>
      <footer className={styles.footer}>
        <div className={styles.footerContent}>
          <p>&copy; {new Date().getFullYear()} Luke McKnight. All rights reserved.</p>
          <div className={styles.footerLinks}>
            <Link to="/privacy">Privacy Policy</Link>
            <Link to="/terms">Terms of Service</Link>
            <a href="mailto:support@teecircle.app">Contact</a>
          </div>
        </div>
      </footer>
    </div>
  )
}
