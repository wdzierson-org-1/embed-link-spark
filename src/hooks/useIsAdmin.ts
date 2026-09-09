import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';

// Whether the signed-in user may open the (temporary) admin dashboard. Reads
// the caller's own admin_users row — the only row RLS lets them see. The
// server re-checks on every admin call; this only decides whether to show
// the way in. Empty admin_users = feature off (see the 20260908120000
// migration).
export const useIsAdmin = (): { isAdmin: boolean; loading: boolean } => {
  const { user, loading: authLoading } = useAuth();
  const userId = user?.id ?? null;
  const [state, setState] = useState<{ forUser: string | null; isAdmin: boolean }>({
    forUser: null,
    isAdmin: false,
  });

  useEffect(() => {
    if (!userId) return;
    let cancelled = false;
    supabase
      .from('admin_users')
      .select('user_id')
      .eq('user_id', userId)
      .maybeSingle()
      .then(({ data, error }) => {
        if (cancelled) return;
        setState({ forUser: userId, isAdmin: !error && !!data });
      });
    return () => {
      cancelled = true;
    };
  }, [userId]);

  if (authLoading) return { isAdmin: false, loading: true };
  if (!userId) return { isAdmin: false, loading: false };
  return { isAdmin: state.forUser === userId && state.isAdmin, loading: state.forUser !== userId };
};
