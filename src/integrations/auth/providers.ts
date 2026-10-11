// src/integrations/auth/providers.ts
// Public identifiers for the id-token sign-in flows (spec §5.1 and §12 "Done 2026-10-11"). These
// are audiences, not secrets: Supabase accepts a Google/Apple identity token only when its `aud`
// is one of the Client IDs configured on the project, and the browser never holds a secret.
export const GOOGLE_WEB_CLIENT_ID = '772942709290-2j03nu08hnumh6jfe2h0j6jkh9bnrbta.apps.googleusercontent.com';
export const APPLE_SERVICES_ID = 'it.gostash.web';
/** Apple requires the registered return URL even for the popup flow: `/auth` on this origin. */
export const appleRedirectUri = () => `${window.location.origin}/auth`;
export const GIS_SRC = 'https://accounts.google.com/gsi/client';
export const APPLE_JS_SRC = 'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js';
