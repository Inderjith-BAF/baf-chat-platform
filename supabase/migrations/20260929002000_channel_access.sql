-- Add per-channel access controls for workspace members.
create table if not exists public.channel_members (
  channel_id uuid not null references public.channels(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(channel_id,user_id)
);

create index if not exists channel_members_user_idx on public.channel_members(user_id);
create index if not exists channel_members_channel_idx on public.channel_members(channel_id);

create or replace function public.is_channel_member(p_channel_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
  select exists(
    select 1
    from public.channel_members cm
    join public.channels c on c.id=cm.channel_id
    where cm.channel_id=p_channel_id
      and cm.user_id=(select auth.uid())
      and public.is_workspace_member(c.workspace_id)
  );
$$;

alter table public.channel_members enable row level security;

drop policy if exists channel_members_read on public.channel_members;
create policy channel_members_read on public.channel_members
for select to authenticated
using (
  user_id=(select auth.uid())
  or exists(select 1 from public.channels c where c.id=channel_id and public.is_workspace_admin(c.workspace_id))
);

drop policy if exists channel_members_admin_insert on public.channel_members;
create policy channel_members_admin_insert on public.channel_members
for insert to authenticated
with check (
  exists(select 1 from public.channels c where c.id=channel_id and public.is_workspace_admin(c.workspace_id))
);

drop policy if exists channel_members_admin_delete on public.channel_members;
create policy channel_members_admin_delete on public.channel_members
for delete to authenticated
using (
  exists(select 1 from public.channels c where c.id=channel_id and public.is_workspace_admin(c.workspace_id))
);

drop policy if exists channels_read on public.channels;
create policy channels_read on public.channels
for select to authenticated
using (
  public.is_channel_member(id)
  or public.is_workspace_admin(workspace_id)
);

drop policy if exists channel_messages_read on public.channel_messages;
create policy channel_messages_read on public.channel_messages
for select to authenticated
using (public.is_channel_member(channel_id));

drop policy if exists channel_messages_insert on public.channel_messages;
create policy channel_messages_insert on public.channel_messages
for insert to authenticated
with check (
  (select auth.uid())=sender_id
  and public.is_channel_member(channel_id)
);

-- Backfill access for all existing active members across existing channels.
insert into public.channel_members(channel_id,user_id)
select c.id,wm.user_id
from public.channels c
join public.workspace_members wm
  on wm.workspace_id=c.workspace_id
where wm.status='active'
on conflict do nothing;

-- Keep the helper executable by authenticated clients only.
grant execute on function public.is_channel_member(uuid) to authenticated;
