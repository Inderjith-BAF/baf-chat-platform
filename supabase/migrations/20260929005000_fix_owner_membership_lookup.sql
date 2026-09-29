-- Provide a safe caller-scoped membership lookup.
-- This avoids client-side RLS ambiguity while never exposing another user's membership.
create or replace function public.get_my_workspace_membership()
returns table(workspace_id uuid, role text, status text)
language sql
stable
security definer
set search_path=''
as $$
  select wm.workspace_id,wm.role,wm.status
  from public.workspace_members wm
  where wm.user_id=(select auth.uid())
  order by wm.created_at asc
  limit 1
$$;

grant execute on function public.get_my_workspace_membership() to authenticated;

-- Ensure the original/oldest BAF Chat account is active.
do $$
declare
  v_user_id uuid;
  v_workspace_id uuid;
begin
  select id into v_user_id from auth.users order by created_at asc limit 1;
  select id into v_workspace_id from public.workspaces where slug='bookairfreight-hq' limit 1;
  if v_user_id is not null and v_workspace_id is not null then
    insert into public.workspace_members(workspace_id,user_id,role,status)
    values(v_workspace_id,v_user_id,'admin','active')
    on conflict(workspace_id,user_id) do update set role='admin',status='active';
    update public.join_requests
      set status='approved',reviewed_at=now()
      where workspace_id=v_workspace_id and user_id=v_user_id;
  end if;
end $$;