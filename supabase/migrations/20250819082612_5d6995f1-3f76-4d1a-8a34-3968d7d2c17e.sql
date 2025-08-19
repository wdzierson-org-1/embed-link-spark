-- First, copy all existing users from auth.users to user_profiles table with random usernames
INSERT INTO public.user_profiles (id, username, display_name, created_at, updated_at)
SELECT 
  au.id,
  LOWER(
    CONCAT(
      CASE (RANDOM() * 10)::INT
        WHEN 0 THEN 'swift'
        WHEN 1 THEN 'bright'
        WHEN 2 THEN 'quick'
        WHEN 3 THEN 'cool'
        WHEN 4 THEN 'blue'
        WHEN 5 THEN 'red'
        WHEN 6 THEN 'zen'
        WHEN 7 THEN 'wave'
        WHEN 8 THEN 'star'
        ELSE 'moon'
      END,
      (RANDOM() * 999 + 100)::INT
    )
  ) as username,
  COALESCE(au.raw_user_meta_data->>'display_name', SPLIT_PART(au.email, '@', 1)) as display_name,
  au.created_at,
  NOW()
FROM auth.users au
LEFT JOIN public.user_profiles up ON au.id = up.id
WHERE up.id IS NULL; -- Only insert users that don't already have profiles

-- Create trigger function to automatically create profile when user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.user_profiles (id, username, display_name, created_at, updated_at)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'username',
    COALESCE(NEW.raw_user_meta_data->>'display_name', SPLIT_PART(NEW.email, '@', 1)),
    NEW.created_at,
    NOW()
  );
  RETURN NEW;
END;
$$;

-- Create trigger to run the function when a new user is created
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();