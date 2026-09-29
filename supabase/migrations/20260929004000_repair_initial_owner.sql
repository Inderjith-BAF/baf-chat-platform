-- Repair the initial BAF Chat owner membership.
-- Safe for the fresh BAF Chat project: the oldest auth account is the owner/admin.
do $$
declare
  v_user_id uuid;
  v_workspace_id uuid;
begin
  select id into v_user_id from auth.users order by created_at asc limit 1;
  if v_user_id is null then
    raise exception 'No auth user exists';
  end if;

  select id into v_workspace_id from public.workspaces where slug='bookairfreight-hq' limit 1;

  if v_workspace_id is null then
    insert into public.workspaces(name,slug,owner_id)
    values('Bookairfreight HQ','bookairfreight-hq',v_user_id)
    returning id into v_workspace_id;
  else
    update public.workspaces set owner_id=v_user_id where id=v_workspace_id;
  end if;

  insert into public.workspace_members(workspace_id,user_id,role,status)
  values(v_workspace_id,v_user_id,'admin','active')
  on conflict(workspace_id,user_id) do update
    set role='admin',status='active';

  update public.join_requests
  set status='approved',reviewed_at=now()
  where workspace_id=v_workspace_id and user_id=v_user_id;

  raise notice 'Initial BAF owner repaired: %',v_user_id;
end $$;