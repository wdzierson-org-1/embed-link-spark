// src/components/auth/appleName.ts
import type { User } from '@supabase/supabase-js';
import { supabase } from '@/integrations/supabase/client';
import { isFallbackDisplayName } from './usernameAvailability';

/**
 * Apple sends the person's name once, on first authorization, and only to the client — so the
 * client writes it: into the user metadata, and onto the profile when the profile still carries a
 * server fallback. A display name the person chose is never overwritten. Either write can be
 * refused without stopping the other; a refusal is logged, since Apple will not send the name again.
 */
export async function writeAppleName(user: User, name: { firstName?: string; lastName?: string }): Promise<void> {
  const full = [name.firstName, name.lastName].filter(Boolean).join(' ').trim();
  if (!full) return;
  const { error: metadataError } = await supabase.auth.updateUser({
    data: { full_name: full, given_name: name.firstName ?? null, family_name: name.lastName ?? null },
  });
  if (metadataError) console.warn('[auth] apple name write failed:', metadataError.message);
  const { data } = await supabase.from('user_profiles').select('username, display_name').eq('id', user.id).maybeSingle();
  if (data && isFallbackDisplayName(data.display_name, data.username, user.email)) {
    const { error: profileError } = await supabase
      .from('user_profiles')
      .update({ display_name: full, first_name: name.firstName ?? null, last_name: name.lastName ?? null })
      .eq('id', user.id);
    if (profileError) console.warn('[auth] apple name write failed:', profileError.message);
  }
}
