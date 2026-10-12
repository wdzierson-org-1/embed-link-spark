-- Capture can create intermediate previews before selecting the final image.
-- The monitor's private account is the only eligible owner. Wait a full day so
-- in-flight enrichment and current previews cannot be mistaken for orphans.
create function public.list_hosted_visual_orphans() returns jsonb
language sql security definer set search_path=public as $$
 select coalesce(jsonb_agg(jsonb_build_object('file_path',x.name)),'[]') from (
 select o.name from storage.objects o join public.hosted_visual_config c on
 o.name ~ ('^'||c.monitor_user_id::text||'/previews/preview_[0-9]+\.(jpe?g|png|webp|gif|avif|heic)$')
 where o.bucket_id='stash-media' and o.created_at<now()-interval '24 hours'
 and not public.hosted_visual_preview_referenced(o.name)
 order by o.created_at,o.name limit 20) x;
$$;
revoke all on function public.list_hosted_visual_orphans() from public,anon,authenticated;
grant execute on function public.list_hosted_visual_orphans() to service_role;
