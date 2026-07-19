import { Routes, Route } from 'react-router-dom'
import { Layout } from './components/Layout'
import { Home } from './pages/Home'
import { Privacy } from './pages/Privacy'
import { Terms } from './pages/Terms'
import { LiveTrip } from './pages/LiveTrip'

function App() {
  return (
    <Routes>
      <Route path="/t/:inviteToken" element={<LiveTrip />} />
      <Route path="/" element={<Layout />}>
        <Route index element={<Home />} />
        <Route path="privacy" element={<Privacy />} />
        <Route path="terms" element={<Terms />} />
      </Route>
    </Routes>
  )
}

export default App
