-- Anonymous sign-ins (try-before-signup on the landing page) have no username
-- metadata, which violated user_profiles.username NOT NULL and made the
-- auth.users trigger fail the whole signup. Guests get a placeholder handle
-- they can change after converting to a real account.
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.user_profiles (id, username, display_name, created_at, updated_at)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'username', 'guest-' || substr(NEW.id::text, 1, 8)),
    COALESCE(NEW.raw_user_meta_data->>'display_name', SPLIT_PART(NEW.email, '@', 1)),
    NEW.created_at,
    NOW()
  );
  RETURN NEW;
END;
$function$;
