import { useEffect, useState } from 'react'

// Ticks once a minute: enough for the greeting, sky and "x min ago".
/** The current time, updated once a minute. */
export function useNow(): Date {
  const [now, setNow] = useState(() => new Date())
  useEffect(() => { const id = setInterval(() => setNow(new Date()), 60_000); return () => clearInterval(id) }, [])
  return now
}
