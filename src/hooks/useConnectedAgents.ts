// src/hooks/useConnectedAgents.ts
import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { useToast } from '@/hooks/use-toast';
import { revokeOAuthGrant } from '@/utils/oauthConsent';
import type { AgentAccessRow } from '@/utils/agentActivity';

export interface ConnectedAgent {
  id: string;
  client_id: string;
  client_name: string;
  client_uri: string | null;
  created_at: string;
  last_used_at: string | null;
  revoked_at: string | null;
}

export const useConnectedAgents = () => {
  const { user, session } = useAuth();
  const { toast } = useToast();
  const [grants, setGrants] = useState<ConnectedAgent[]>([]);
  const [activity, setActivity] = useState<AgentAccessRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [revoking, setRevoking] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    const [grantsRes, activityRes] = await Promise.all([
      supabase.from('agent_grants')
        .select('id, client_id, client_name, client_uri, created_at, last_used_at, revoked_at')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false }),
      supabase.from('agent_access_log')
        .select('id, client_id, tool, query, filters, item_id, item_title, result_count, created_at')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })
        .limit(50),
    ]);
    if (grantsRes.error || activityRes.error) {
      console.error('connected agents load failed:', grantsRes.error ?? activityRes.error);
      toast({ title: 'Could not load connected agents', description: 'Reload the page to try again.', variant: 'destructive' });
    }
    setGrants((grantsRes.data ?? []) as ConnectedAgent[]);
    setActivity((activityRes.data ?? []) as AgentAccessRow[]);
    setLoading(false);
  }, [user, toast]);

  useEffect(() => { load(); }, [load]);

  const clientNameFor = useCallback(
    (clientId: string) => grants.find((g) => g.client_id === clientId)?.client_name ?? 'An agent',
    [grants],
  );

  // Supabase first (kills the client's sessions + refresh tokens), then our
  // row (closes the MCP door for tokens still inside their hour).
  const revoke = async (grant: ConnectedAgent) => {
    if (!session?.access_token) return;
    setRevoking(grant.id);
    try {
      await revokeOAuthGrant(grant.client_id, session.access_token);
      const { error } = await supabase.from('agent_grants')
        .update({ revoked_at: new Date().toISOString() })
        .eq('id', grant.id);
      if (error) throw error;
      toast({ title: `${grant.client_name} disconnected` });
      await load();
    } catch (e) {
      console.error('revoke failed:', e);
      toast({ title: 'Could not disconnect', description: 'Try again in a moment.', variant: 'destructive' });
    } finally {
      setRevoking(null);
    }
  };

  return {
    active: grants.filter((g) => !g.revoked_at),
    activity,
    loading,
    revoke,
    revoking,
    clientNameFor,
  };
};
