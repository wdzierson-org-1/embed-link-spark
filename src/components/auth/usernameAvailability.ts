// src/components/auth/usernameAvailability.ts
import { supabase } from '@/integrations/supabase/client';

/** What the forms accept and the DB lock trigger enforces on change (spec §4.3) */
export const USERNAME_RE = /^[a-z0-9]{3,20}$/;

/** Accents fold into their letters first (NFKD, then the combining marks go): José García → josegarcia */
export const sanitizeUsername = (input: string) =>
  input.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 20);

/** A handle suggested from a provider name ("Will Dzierson" → willdzierson), or null if too short */
export const suggestHandle = (fullName?: string | null) => {
  const s = sanitizeUsername(fullName ?? '');
  return s.length >= 3 ? s : null;
};

// Apple's Hide My Email addresses: the local part is random characters, so the trigger never names anyone after it
const APPLE_RELAY_DOMAIN = 'privaterelay.appleid.com';
const text = (v: unknown) => (typeof v === 'string' ? v : undefined);

/**
 * What the claim step's field starts with (spec §4.3), most personal first: the name the provider
 * gave us, else the email's local part (never a relay address's, as in the trigger), else the
 * server's own handle when the forms would accept it, else nothing. The email comes before the
 * server's handle because a name that sanitizes to nothing (a non-Latin one) leaves the server a
 * digit-padded handle (123) where the email still says ivanpetrov. A guest-shaped server handle
 * (guest-ab12cd34) fails the format, so it is never the prefill. `nameOverride` is a name the client
 * learned in this very sign-in (Apple's, which the metadata may not hold yet) and outranks the
 * metadata's. A prefill that turns out to be taken gives way to the server's handle in HandleStep.
 */
export const handlePrefill = (
  user: { email?: string | null; user_metadata?: Record<string, unknown> },
  serverUsername: string,
  nameOverride?: string | null,
): string => {
  const fullName = text(user.user_metadata?.full_name) ?? text(user.user_metadata?.name);
  const [local, domain = ''] = (user.email ?? '').split('@');
  const emailLocalPart = domain.toLowerCase() === APPLE_RELAY_DOMAIN ? '' : local;
  return suggestHandle(nameOverride ?? fullName) ?? suggestHandle(emailLocalPart) ?? (USERNAME_RE.test(serverUsername) ? serverUsername : '');
};

/** The server's display-name fallbacks (spec §4.4): nothing, the handle itself, or the email's local part */
export const isFallbackDisplayName = (displayName: string | null | undefined, username: string, email?: string | null) => {
  const local = (email ?? '').split('@')[0];
  return !displayName || displayName === username || (local !== '' && displayName === local);
};

/** Live availability probe; a person's own row never counts as taken */
export async function isUsernameTaken(username: string, exceptUserId?: string): Promise<boolean> {
  const { data, error } = await supabase.from('user_profiles').select('id').eq('username', username).maybeSingle();
  if (error) {
    console.error('Error checking username:', error);
    return false;
  }
  return !!data && data.id !== exceptUserId;
}
