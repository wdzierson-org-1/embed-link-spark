import { useState, useEffect, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from './useAuth';

export interface FollowCounts {
  followers: number;
  following: number;
}

export const useFollows = (profileUserId?: string) => {
  const { user } = useAuth();
  const currentUserId = user?.id;
  const [isFollowing, setIsFollowing] = useState<boolean>(false);
  const [counts, setCounts] = useState<FollowCounts>({ followers: 0, following: 0 });
  const [loading, setLoading] = useState(false);

  const loadFollowState = useCallback(async () => {
    if (!profileUserId) return;

    try {
      // Get follower count
      const { data: followerData, error: followerError } = await supabase
        .rpc('get_follower_count', { user_id: profileUserId });

      if (followerError) throw followerError;

      // Get following count
      const { data: followingData, error: followingError } = await supabase
        .rpc('get_following_count', { user_id: profileUserId });

      if (followingError) throw followingError;

      setCounts({
        followers: Number(followerData) || 0,
        following: Number(followingData) || 0,
      });
    } catch (error) {
      console.error('Error loading follow counts:', error);
    }
  }, [profileUserId]);

  const checkIsFollowing = useCallback(async () => {
    if (!currentUserId || !profileUserId || currentUserId === profileUserId) return;

    try {
      const { data, error } = await supabase
        .rpc('is_following', { target_id: profileUserId });

      if (error) throw error;
      setIsFollowing(!!data);
    } catch (error) {
      console.error('Error checking follow status:', error);
    }
  }, [currentUserId, profileUserId]);

  useEffect(() => {
    loadFollowState();
    checkIsFollowing();
  }, [loadFollowState, checkIsFollowing]);

  const follow = useCallback(async () => {
    if (!currentUserId || !profileUserId || currentUserId === profileUserId) return;
    setLoading(true);
    try {
      const { error } = await supabase
        .rpc('follow_user', { target_id: profileUserId });

      if (error) throw error;

      setIsFollowing(true);
      setCounts(prev => ({ ...prev, followers: prev.followers + 1 }));
    } catch (error) {
      console.error('Error following user:', error);
    } finally {
      setLoading(false);
    }
  }, [currentUserId, profileUserId]);

  const unfollow = useCallback(async () => {
    if (!currentUserId || !profileUserId || currentUserId === profileUserId) return;
    setLoading(true);
    try {
      const { error } = await supabase
        .rpc('unfollow_user', { target_id: profileUserId });

      if (error) throw error;

      setIsFollowing(false);
      setCounts(prev => ({ ...prev, followers: prev.followers - 1 }));
    } catch (error) {
      console.error('Error unfollowing user:', error);
    } finally {
      setLoading(false);
    }
  }, [currentUserId, profileUserId]);

  return {
    isFollowing,
    counts,
    loading,
    follow,
    unfollow,
    isOwnProfile: currentUserId === profileUserId,
    canFollow: !!currentUserId && !!profileUserId && currentUserId !== profileUserId,
  };
};
