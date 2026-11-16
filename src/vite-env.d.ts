/// <reference types="vite/client" />
declare module '*.mjs'
/** The commit this build is from (vite.config.ts), or 'dev'. */
declare const __BUILD_SHA__: string
/** When this build was made or deployed, ISO 8601. */
declare const __BUILT_AT__: string
