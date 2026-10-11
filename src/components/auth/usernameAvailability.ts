// src/components/auth/usernameAvailability.ts
import { supabase } from '@/integrations/supabase/client';

/** What the forms accept and the DB lock trigger enforces on change (spec §4.3) */
export const USERNAME_RE = /^[a-z0-9]{3,20}$/;

export const sanitizeUsername = (input: string) => input.toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 20);

/** A handle suggested from a provider name ("Will Dzierson" → willdzierson), or null if too short */
export const suggestHandle = (fullName?: string | null) => {
  const s = sanitizeUsername(fullName ?? '');
  return s.length >= 3 ? s : null;
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
