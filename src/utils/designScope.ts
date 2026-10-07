/**
 * Which design system a route renders in. The signed-in app (and the pages that share its
 * header and cards) moved to DESIGN-v2 on 2026-10-06, and the way in (sign in / sign up, and
 * choosing a new password) on 2026-10-07; marketing, pricing, legal and the agent-consent screen
 * keep DESIGN.md (v1) until the homepage prototype is ported. `DesignScope` applies it.
 */
export const V2_ROUTE_PREFIXES = ['/home', '/settings', '/discover', '/feed/', '/admin', '/design/', '/auth', '/reset-password'];

export const isV2Route = (pathname: string): boolean =>
  V2_ROUTE_PREFIXES.some((prefix) =>
    prefix.endsWith('/') ? pathname.startsWith(prefix) : pathname === prefix || pathname.startsWith(`${prefix}/`),
  );
