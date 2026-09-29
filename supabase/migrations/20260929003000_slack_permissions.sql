-- Finalize Slack-style channel visibility and member-created channels.
-- Public channels: every active workspace member can access.
-- Private channels: only channel_members (plus the creator) can access.
-- Workspace admins do not get implicit access to private channels.

create or replace function public.is_channel_member(p_channel_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
  select exists(
    select 1
    from public.channels c
    where c.id=p_channel_id
      and public.is_workspace_member(c.workspace_id)
      and (
        c.is_private = false
        or c.created_by = (select auth.uid())
        or exists(
          select 1 from public.channel_members cm
          where cm.channel_id=c.id and cm.user_id=(select auth.uid())
        )
      )
  );
$$;

drop policy if exists channels_read on public.channels;
create policy channels_read on public.channels
for select to authenticated using (public.is_channel_member(id));

drop policy if exists channels_admin_insert on public.channels;
create policy channels_member_insert on public.channels
for insert to authenticated
with check (created_by=(select auth.uid()) and public.is_workspace_member(workspace_id));

drop policy if exists channel_messages_read on public.channel_messages;
create policy channel_messages_read on public.channel_messages
for select to authenticated using (public.is_channel_member(channel_id));

drop policy if exists channel_messages_insert on public.channel_messages;
create policy channel_messages_insert on public.channel_messages
for insert to authenticated
with check ((select auth.uid())=sender_id and public.is_channel_member(channel_id));

drop policy if exists channel_members_admin_insert on public.channel_members;
create policy channel_members_creator_or_admin_insert on public.channel_members
for insert to authenticated
with check (
  exists(
    select 1 from public.channels c
    where c.id=channel_id
      and (c.created_by=(select auth.uid()) or public.is_workspace_admin(c.workspace_id))
  )
);

drop policy if exists channel_members_admin_delete on public.channel_members;
create policy channel_members_creator_or_admin_delete on public.channel_members
for delete to authenticated
using (
  exists(
    select 1 from public.channels c
    where c.id=channel_id
      and (c.created_by=(select auth.uid()) or public.is_workspace_admin(c.workspace_id))
  )
);

grant execute on function public.is_channel_member(uuid) to authenticated;
