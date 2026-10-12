begin;
do $$
declare owner uuid; foreign_owner uuid:=gen_random_uuid(); result jsonb; p text; item uuid:=gen_random_uuid();
begin
 select monitor_user_id into owner from hosted_visual_config;
 if owner is null then raise exception 'configured monitor required for cleanup assertion'; end if;
 p:=owner::text||'/previews/preview_9999900000000.jpeg';
 -- Only metadata fixtures in a rolled-back transaction; no object bytes altered.
 insert into storage.objects(bucket_id,name,created_at) values
 ('stash-media',p,now()-interval '25 hours'),
 ('stash-media',owner::text||'/previews/preview_9999900000001.jpeg',now()),
 ('stash-media',foreign_owner::text||'/previews/preview_9999900000002.jpeg',now()-interval '25 hours'),
 ('stash-media',owner::text||'/previews/preview_9999900000003.jpeg',now()-interval '25 hours');
 insert into items(id,user_id,type,url,title,file_path,is_public) values(item,owner,'link','https://example.org/orphan-test','test',owner::text||'/previews/preview_9999900000003.jpeg',false);
 result:=list_hosted_visual_orphans();
 if not result @> jsonb_build_array(jsonb_build_object('file_path',p)) then raise exception 'old orphan not selected'; end if;
 if result @> jsonb_build_array(jsonb_build_object('file_path',owner::text||'/previews/preview_9999900000001.jpeg')) then raise exception 'recent preview selected'; end if;
 if result @> jsonb_build_array(jsonb_build_object('file_path',foreign_owner::text||'/previews/preview_9999900000002.jpeg')) then raise exception 'foreign preview selected'; end if;
 if result @> jsonb_build_array(jsonb_build_object('file_path',owner::text||'/previews/preview_9999900000003.jpeg')) then raise exception 'referenced preview selected'; end if;
 if has_function_privilege('authenticated','public.list_hosted_visual_orphans()','EXECUTE') then raise exception 'client can inspect previews'; end if;
end $$;
select 'visual_orphan_cleanup_assertions_passed' as assertion;
rollback;
