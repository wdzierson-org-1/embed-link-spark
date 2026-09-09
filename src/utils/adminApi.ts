import { supabase } from '@/integrations/supabase/client';
import type { AdminUserRow } from '@/utils/adminStats';

// Client for the temporary admin dashboard's edge function
// (supabase/functions/admin-stats). Both calls are read-only and refused
// with 403 unless the caller has an admin_users row.

export interface AdminMember {
  user_id: string;
  email: string | null;
  username: string | null;
  display_name: string | null;
  created_at: string;
}

export interface AdminLibrary {
  user: AdminMember;
  // Library rows exactly as the grid loads them (ITEM_LIST_COLUMN_NAMES + user_id)
  items: Record<string, unknown>[];
}

// A FunctionsHttpError carries the Response; the server's { error } text is
// more useful than "Edge Function returned a non-2xx status code"
export const describeInvokeError = async (error: { message?: string; context?: unknown }): Promise<string> => {
  const ctx = error.context as { json?: () => Promise<{ error?: string }> } | undefined;
  if (ctx && typeof ctx.json === 'function') {
    try {
      const body = await ctx.json();
      if (body?.error) return body.error;
    } catch {
      // body was not JSON — fall through to the client message
    }
  }
  return error.message || 'Request failed';
};

const call = async <T,>(body: Record<string, unknown>): Promise<T> => {
  const { data, error } = await supabase.functions.invoke('admin-stats', { body });
  if (error) throw new Error(await describeInvokeError(error));
  return data as T;
};

export const fetchAdminUsers = async (): Promise<AdminUserRow[]> =>
  (await call<{ users: AdminUserRow[] }>({ action: 'users' })).users;

export const fetchAdminLibrary = (userId: string): Promise<AdminLibrary> =>
  call<AdminLibrary>({ action: 'items', user_id: userId });
