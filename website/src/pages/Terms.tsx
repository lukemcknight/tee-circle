import styles from './Legal.module.css'

export function Terms() {
  return (
    <div className={styles.container}>
      <h1>Terms of Service</h1>
      <p className={styles.updated}>Last updated: December 30, 2024</p>

      <section>
        <h2>1. Acceptance of Terms</h2>
        <p>
          By accessing or using TeeCircle ("the App"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree to these Terms, please do not use the App.
        </p>
      </section>

      <section>
        <h2>2. Description of Service</h2>
        <p>
          TeeCircle is a mobile application that allows users to organize golf rounds, invite friends, and manage RSVPs. The service is provided "as is" and we reserve the right to modify, suspend, or discontinue the service at any time.
        </p>
      </section>

      <section>
        <h2>3. User Accounts</h2>
        <p>To use TeeCircle, you must:</p>
        <ul>
          <li>Create an account with a valid email address</li>
          <li>Be at least 13 years of age</li>
          <li>Provide accurate and complete information</li>
          <li>Maintain the security of your account credentials</li>
          <li>Notify us immediately of any unauthorized use of your account</li>
        </ul>
        <p>
          You are responsible for all activities that occur under your account.
        </p>
      </section>

      <section>
        <h2>4. Acceptable Use</h2>
        <p>You agree not to:</p>
        <ul>
          <li>Use the App for any unlawful purpose</li>
          <li>Harass, abuse, or harm other users</li>
          <li>Impersonate any person or entity</li>
          <li>Interfere with or disrupt the App or servers</li>
          <li>Attempt to gain unauthorized access to any part of the App</li>
          <li>Use automated means to access the App without permission</li>
          <li>Upload viruses or malicious code</li>
          <li>Collect user information without consent</li>
        </ul>
      </section>

      <section>
        <h2>5. User Content</h2>
        <p>
          You retain ownership of content you create (such as round details and profile information). By posting content, you grant us a non-exclusive, worldwide, royalty-free license to use, display, and distribute your content as necessary to provide the service.
        </p>
        <p>
          You are solely responsible for your content and must ensure it does not violate any laws or these Terms.
        </p>
      </section>

      <section>
        <h2>6. Privacy</h2>
        <p>
          Your use of TeeCircle is also governed by our <a href="/privacy">Privacy Policy</a>, which describes how we collect, use, and protect your information.
        </p>
      </section>

      <section>
        <h2>7. Intellectual Property</h2>
        <p>
          TeeCircle and its original content, features, and functionality are owned by us and are protected by international copyright, trademark, and other intellectual property laws.
        </p>
      </section>

      <section>
        <h2>8. Third-Party Services</h2>
        <p>
          The App may contain links to or integrate with third-party services. We are not responsible for the content, privacy policies, or practices of third-party services.
        </p>
      </section>

      <section>
        <h2>9. Disclaimer of Warranties</h2>
        <p>
          THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED. WE DO NOT WARRANT THAT THE APP WILL BE UNINTERRUPTED, ERROR-FREE, OR FREE OF VIRUSES OR OTHER HARMFUL COMPONENTS.
        </p>
      </section>

      <section>
        <h2>10. Limitation of Liability</h2>
        <p>
          TO THE MAXIMUM EXTENT PERMITTED BY LAW, WE SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING LOSS OF PROFITS, DATA, OR GOODWILL, ARISING FROM YOUR USE OF THE APP.
        </p>
      </section>

      <section>
        <h2>11. Indemnification</h2>
        <p>
          You agree to indemnify and hold harmless TeeCircle and its officers, directors, employees, and agents from any claims, damages, losses, or expenses arising from your use of the App or violation of these Terms.
        </p>
      </section>

      <section>
        <h2>12. Termination</h2>
        <p>
          We may terminate or suspend your account and access to the App immediately, without prior notice, for conduct that we believe violates these Terms or is harmful to other users, us, or third parties, or for any other reason at our sole discretion.
        </p>
      </section>

      <section>
        <h2>13. Changes to Terms</h2>
        <p>
          We reserve the right to modify these Terms at any time. We will provide notice of significant changes by posting the updated Terms in the App or on our website. Your continued use of the App after changes constitutes acceptance of the new Terms.
        </p>
      </section>

      <section>
        <h2>14. Governing Law</h2>
        <p>
          These Terms shall be governed by and construed in accordance with the laws of the United States, without regard to its conflict of law provisions.
        </p>
      </section>

      <section>
        <h2>15. Contact Us</h2>
        <p>
          If you have any questions about these Terms, please contact us at:
        </p>
        <p>
          <a href="mailto:support@teecircle.app">support@teecircle.app</a>
        </p>
      </section>
    </div>
  )
}
