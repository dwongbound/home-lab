// A handful of hand-drawn 20px icons. Inline so there is no icon library
// in the bundle (bundle-barrel-imports).
const PATHS = {
  home: 'M3.5 9.5 10 4l6.5 5.5V16a1 1 0 0 1-1 1H12v-4.5H8V17H4.5a1 1 0 0 1-1-1z',
  services: 'M4 4.5h12v4H4zM4 11.5h12v4H4zM6.5 6.5h.01M6.5 13.5h.01',
  schedule: 'M10 17a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM10 6.5V10l2.5 1.5',
  settings: 'M10 12.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5zM10 2.5v2M10 15.5v2M2.5 10h2M15.5 10h2M4.7 4.7l1.4 1.4M13.9 13.9l1.4 1.4M4.7 15.3l1.4-1.4M13.9 6.1l1.4-1.4',
  external: 'M8 4.5H4.5v11h11V12M11 4.5h4.5V9M15.5 4.5 9 11',
  chip: 'M6 6h8v8H6zM8 3v3M12 3v3M8 14v3M12 14v3M3 8h3M3 12h3M14 8h3M14 12h3',
  memory: 'M3 6.5h14v7H3zM6 9h.01M9 9h.01M12 9h.01M6 13.5v2M10 13.5v2M14 13.5v2',
  gpu: 'M2.5 5.5h15v9h-15zM7 10a2 2 0 1 0 4 0 2 2 0 0 0-4 0zM14.5 8v4',
  disk: 'M3.5 12h13l-2-7h-9zM3.5 12v3h13v-3M13.5 13.5h.01',
  claude: 'M10 3v14M3 10h14M5 5l10 10M15 5 5 15',
  bulb: 'M7.5 14.5h5M8 17h4M10 3a5 5 0 0 0-3 9c.6.5 1 1.2 1 2h4c0-.8.4-1.5 1-2a5 5 0 0 0-3-9z',
  money: 'M2.5 5.5h15v9h-15zM10 12a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM5 8v4M15 8v4',
  // Four corners pointing out: kiosk mode (full screen).
  expand: 'M3.5 7.5v-4h4M12.5 3.5h4v4M16.5 12.5v4h-4M7.5 16.5h-4v-4',
  refresh: 'M15.5 8A6 6 0 0 0 4.6 6.5M4.5 3.5v3h3M4.5 12a6 6 0 0 0 10.9 1.5M15.5 16.5v-3h-3',
  // Home page devices.
  power: 'M10 3v6.5M6.2 5.6a6 6 0 1 0 7.6 0',
  play: 'M7 4.5v11l8.5-5.5z',
  pause: 'M7.5 5v10M12.5 5v10',
  toggle: 'M6.5 6h7a4 4 0 0 1 0 8h-7a4 4 0 0 1 0-8zM13.5 10h.01',
  fan: 'M10 11.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3zM10 8.5c-.5-3 .5-5 2.5-5s2 3-1.5 5.5M11.5 10.5c3-.5 5 .5 5 2.5s-3 2-5.5-1.5M8.5 10.5c-2 2.5-4.5 3-5.5 1.5s1-3.5 4.5-3',
  speaker: 'M5.5 3h9v14h-9zM10 14a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5zM10 6h.01',
  tv: 'M2.5 4.5h15v9.5h-15zM7 17h6',
  moon: 'M16 12.5A6.5 6.5 0 0 1 7.5 4a6.5 6.5 0 1 0 8.5 8.5z',
  sparkle: 'M10 3l1.6 4.4L16 9l-4.4 1.6L10 15l-1.6-4.4L4 9l4.4-1.6z',
} as const

export type IconName = keyof typeof PATHS

/** One icon. Decorative: the control around it carries the label. */
export function Icon({ name, size = 18 }: { name: IconName; size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
      <path d={PATHS[name]} />
    </svg>
  )
}
