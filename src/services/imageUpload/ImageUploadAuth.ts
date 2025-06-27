
import { supabase } from '@/integrations/supabase/client';

export const validateAuthentication = async (userId: string): Promise<void> => {
  console.log('ImageUploadAuth: Validating authentication');
  
  // First, try to refresh the session to ensure it's current
  const { data: { session: refreshedSession }, error: refreshError } = await supabase.auth.refreshSession();
  
  if (refreshError) {
    console.error('ImageUploadAuth: Session refresh failed:', refreshError);
    // Continue with existing session if refresh fails
  }

  // Get the current session (either refreshed or existing)
  const { data: { session }, error: sessionError } = await supabase.auth.getSession();
  
  if (sessionError) {
    console.error('ImageUploadAuth: Session error:', sessionError);
    throw new Error('Failed to authenticate - session error');
  }

  if (!session?.user) {
    console.error('ImageUploadAuth: No user in session');
    throw new Error('Authentication required for file upload');
  }

  // Log detailed authentication information
  console.log('ImageUploadAuth: Authentication successful', {
    sessionUserId: session.user.id,
    providedUserId: userId,
    userMatches: session.user.id === userId,
    sessionExpiry: session.expires_at,
    currentTime: new Date().toISOString()
  });

  // Verify user ID matches session
  if (session.user.id !== userId) {
    console.error('ImageUploadAuth: User ID mismatch', { 
      sessionUserId: session.user.id, 
      providedUserId: userId 
    });
    throw new Error('User ID mismatch');
  }
};
