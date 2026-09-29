-- Bootstrap the first Bookairfreight Chat workspace.
-- This migration is intended for the fresh BAF Chat Supabase project.
-- The first account created in this project becomes the initial workspace owner/admin.

do $$
declare
  v_user_id uuid;
  v_workspace_id uuid;
begin
  select id into v_user_id
  from auth.users
  order by created_at asc
  limit 1;

  if v_user_id is null then
    raise exception 'No auth user exists. Create the first BAF Chat account before applying this migration.';
  end if;

  insert into public.workspaces(name, slug, owner_id)
  values ('Bookairfreight HQ', 'bookairfreight-hq', v_user_id)
  on conflict (slug) do update
    set owner_id = excluded.owner_id
  returning id into v_workspace_id;

  insert into public.workspace_members(workspace_id, user_id, role, status)
  values (v_workspace_id, v_user_id, 'admin', 'active')
  on conflict (workspace_id, user_id) do update
    set role = 'admin', status = 'active';

  insert into public.channels(workspace_id, name, slug, emoji, created_by)
  values
    (v_workspace_id, 'Team HQ', 'general', '👋', v_user_id),
    (v_workspace_id, 'Marketing', 'marketing', '📣', v_user_id),
    (v_workspace_id, 'Outbound Squad', 'outbound-squad', '🚀', v_user_id),
    (v_workspace_id, 'Campaigns', 'campaigns', '🎯', v_user_id),
    (v_workspace_id, 'Content Lab', 'content-lab', '🎨', v_user_id),
    (v_workspace_id, 'Random', 'random', '🎲', v_user_id)
  on conflict (workspace_id, slug) do nothing;

  update public.join_requests
  set status = 'approved', reviewed_at = now()
  where workspace_id = v_workspace_id
    and user_id = v_user_id;

  raise notice 'BAF Chat workspace bootstrapped for user %', v_user_id;
end $$;
