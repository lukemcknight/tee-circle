import styles from './Legal.module.css'

export function Privacy() {
  return (
    <div className={styles.container}>
      <h1>Privacy Policy</h1>
      <p className={styles.updated}>Last updated: December 30, 2024</p>

      <section>
        <h2>Introduction</h2>
        <p>
          TeeCircle ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application.
        </p>
        <p>
          Please read this Privacy Policy carefully. By using TeeCircle, you agree to the collection and use of information in accordance with this policy.
        </p>
      </section>

      <section>
        <h2>Information We Collect</h2>

        <h3>Personal Information</h3>
        <p>We collect information you provide directly to us, including:</p>
        <ul>
          <li><strong>Account Information:</strong> When you create an account, we collect your email address, full name, and username.</li>
          <li><strong>Golf Round Data:</strong> Information about golf rounds you create, including course names, tee times, and round preferences (holes, walking/riding).</li>
          <li><strong>Social Connections:</strong> Information about your friend connections and round invitations within the app.</li>
          <li><strong>RSVP Responses:</strong> Your responses to round invitations (yes, no, or pending).</li>
        </ul>

        <h3>Automatically Collected Information</h3>
        <p>When you use TeeCircle, we may automatically collect:</p>
        <ul>
          <li><strong>Device Information:</strong> Device type, operating system, and unique device identifiers.</li>
          <li><strong>Push Notification Tokens:</strong> If you enable push notifications, we collect tokens to send you notifications about round updates and friend requests.</li>
        </ul>
      </section>

      <section>
        <h2>How We Use Your Information</h2>
        <p>We use the information we collect to:</p>
        <ul>
          <li>Provide, maintain, and improve TeeCircle</li>
          <li>Create and manage your account</li>
          <li>Enable you to create golf rounds and invite friends</li>
          <li>Send push notifications about round updates, friend requests, and RSVPs</li>
          <li>Respond to your comments, questions, and support requests</li>
          <li>Monitor and analyze trends, usage, and activities</li>
          <li>Detect, investigate, and prevent fraudulent transactions and abuse</li>
        </ul>
      </section>

      <section>
        <h2>Information Sharing</h2>
        <p>We may share your information in the following circumstances:</p>
        <ul>
          <li><strong>With Other Users:</strong> Your username, name, and round participation are visible to friends and other users you interact with.</li>
          <li><strong>Service Providers:</strong> We use third-party services including Supabase (database and authentication) and Expo (push notifications) to operate our app.</li>
          <li><strong>Legal Requirements:</strong> We may disclose information if required by law or in response to valid legal requests.</li>
        </ul>
        <p>We do not sell your personal information to third parties.</p>
      </section>

      <section>
        <h2>Data Storage and Security</h2>
        <p>
          Your data is stored securely using Supabase, a trusted database provider. We implement appropriate technical and organizational measures to protect your personal information against unauthorized access, alteration, disclosure, or destruction.
        </p>
        <p>
          Authentication tokens are stored securely on your device using encrypted storage.
        </p>
      </section>

      <section>
        <h2>Your Rights and Choices</h2>
        <p>You have the following rights regarding your data:</p>
        <ul>
          <li><strong>Access:</strong> You can access your personal information through the app's profile section.</li>
          <li><strong>Update:</strong> You can update your username and profile information at any time.</li>
          <li><strong>Delete:</strong> You can request deletion of your account and associated data by contacting us.</li>
          <li><strong>Push Notifications:</strong> You can disable push notifications through your device settings.</li>
        </ul>
      </section>

      <section>
        <h2>Data Retention</h2>
        <p>
          We retain your personal information for as long as your account is active or as needed to provide you services. If you delete your account, we will delete or anonymize your personal information within 30 days, except where we need to retain it for legal purposes.
        </p>
      </section>

      <section>
        <h2>Children's Privacy</h2>
        <p>
          TeeCircle is not intended for children under the age of 13. We do not knowingly collect personal information from children under 13. If we learn that we have collected information from a child under 13, we will delete that information promptly.
        </p>
      </section>

      <section>
        <h2>Changes to This Policy</h2>
        <p>
          We may update this Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy on this page and updating the "Last updated" date.
        </p>
      </section>

      <section>
        <h2>Contact Us</h2>
        <p>
          If you have any questions about this Privacy Policy or our privacy practices, please contact us at:
        </p>
        <p>
          <a href="mailto:support@teecircle.app">support@teecircle.app</a>
        </p>
      </section>
    </div>
  )
}
