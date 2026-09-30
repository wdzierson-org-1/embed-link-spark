import { authenticateUser } from './auth.ts';
/** Service-to-service or a verified owner; never trust a body-supplied user ID. */
export async function requireItemAccess(req: Request, db: any, itemId: string, columns = '*') {
  const header = req.headers.get('authorization');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const isService = !!serviceKey && header === `Bearer ${serviceKey}`;
  let query = db.from('items').select(columns).eq('id', itemId);
  if (!isService) {
    const { user } = await authenticateUser(header);
    query = query.eq('user_id', user.id);
  }
  const { data, error } = await query.maybeSingle();
  if (error) throw error;
  if (!data) throw new Error('Item not found or access denied');
  return data;
}
