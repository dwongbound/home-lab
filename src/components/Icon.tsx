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
  money: 'M2.5 5.5h15v9h-15zM10 12a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM5 8v4M15 8v4',
  refresh: 'M15.5 8A6 6 0 0 0 4.6 6.5M4.5 3.5v3h3M4.5 12a6 6 0 0 0 10.9 1.5M15.5 16.5v-3h-3',
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
