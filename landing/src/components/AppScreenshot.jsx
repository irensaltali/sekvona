import profilesScreenshot from '../assets/sekvona-profiles-demo.webp'

export default function AppScreenshot() {
  return (
    <div className="app-screenshot-section">
      <div className="inner">
        <figure className="app-screenshot">
          <img
            src={profilesScreenshot}
            alt="Sekvona desktop app showing six browser profiles with tags and CloakBrowser and Camoufox engines"
            width="2160"
            height="1260"
          />
          <figcaption>Sekvona desktop app with demo profiles</figcaption>
        </figure>
      </div>
    </div>
  )
}
