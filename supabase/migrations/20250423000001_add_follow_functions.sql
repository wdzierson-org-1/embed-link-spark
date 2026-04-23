-- Follow/unfollow stored procedures for user_follows table

-- Follow a user (idempotent)
CREATE OR REPLACE FUNCTION follow_user(target_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID;
BEGIN
  current_user_id := auth.uid();
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF current_user_id = target_id THEN
    RAISE EXCEPTION 'Cannot follow yourself';
  END IF;

  INSERT INTO user_follows (follower_id, following_id)
  VALUES (current_user_id, target_id)
  ON CONFLICT (follower_id, following_id) DO NOTHING;

  RETURN TRUE;
END;
$$;

-- Unfollow a user
CREATE OR REPLACE FUNCTION unfollow_user(target_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID;
BEGIN
  current_user_id := auth.uid();
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  DELETE FROM user_follows
  WHERE follower_id = current_user_id AND following_id = target_id;

  RETURN TRUE;
END;
$$;

-- Get follower count for a user
CREATE OR REPLACE FUNCTION get_follower_count(user_id UUID)
RETURNS BIGINT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT COUNT(*)::BIGINT FROM user_follows WHERE following_id = user_id;
$$;

-- Get following count for a user
CREATE OR REPLACE FUNCTION get_following_count(user_id UUID)
RETURNS BIGINT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT COUNT(*)::BIGINT FROM user_follows WHERE follower_id = user_id;
$$;

-- Check if current user follows target user
CREATE OR REPLACE FUNCTION is_following(target_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_follows
    WHERE follower_id = auth.uid() AND following_id = target_id
  );
$$;
