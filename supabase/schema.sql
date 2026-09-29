-- BAF Chat production schema
create extension if not exists pgcrypto;

create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null,
 avatar_url text,
 status text not null default 'offline' check(status in('online','away','offline')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.workspaces (
 id uuid primary key default gen_random_uuid(),
 name text not null,
 slug text unique not null,
 owner_id uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now()
);
create table if not exists public.workspace_members (
 workspace_id uuid not null references public.workspaces(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 role text not null default 'member' check(role in('admin','member')),
 status text not null default 'active' check(status in('pending','active','suspended')),
 created_at timestamptz not null default now(),
 primary key(workspace_id,user_id)
);
create table if not exists public.channels (
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references public.workspaces(id) on delete cascade,
 name text not null,
 slug text not null,
 emoji text not null default '💬',
 is_private boolean not null default false,
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 unique(workspace_id,slug)
);
create table if not exists public.channel_messages (
 id uuid primary key default gen_random_uuid(),
 channel_id uuid not null references public.channels(id) on delete cascade,
 sender_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check(length(trim(body)) between 1 and 10000),
 created_at timestamptz not null default now(),
 edited_at timestamptz
);
create table if not exists public.message_reactions (
 message_id uuid not null references public.channel_messages(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 emoji text not null,
 created_at timestamptz not null default now(),
 primary key(message_id,user_id,emoji)
);
create table if not exists public.dm_threads (
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references public.workspaces(id) on delete cascade,
 created_at timestamptz not null default now()
);
create table if not exists public.dm_participants (
 thread_id uuid not null references public.dm_threads(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 primary key(thread_id,user_id)
);
create table if not exists public.dm_messages (
 id uuid primary key default gen_random_uuid(),
 thread_id uuid not null references public.dm_threads(id) on delete cascade,
 sender_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check(length(trim(body)) between 1 and 10000),
 created_at timestamptz not null default now()
);
create table if not exists public.join_requests (
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references public.workspaces(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 email text not null,
 requested_name text not null,
 status text not null default 'pending' check(status in('pending','approved','rejected')),
 created_at timestamptz not null default now(),
 reviewed_at timestamptz,
 unique(workspace_id,user_id)
);

create index if not exists workspace_members_user_idx on public.workspace_members(user_id);
create index if not exists channels_workspace_idx on public.channels(workspace_id);
create index if not exists channel_messages_channel_created_idx on public.channel_messages(channel_id,created_at);
create index if not exists dm_participants_user_idx on public.dm_participants(user_id);
create index if not exists dm_messages_thread_created_idx on public.dm_messages(thread_id,created_at);

create or replace function public.is_workspace_member(p_workspace_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.workspace_members wm where wm.workspace_id=p_workspace_id and wm.user_id=(select auth.uid()) and wm.status='active') $$;
create or replace function public.is_workspace_admin(p_workspace_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.workspace_members wm where wm.workspace_id=p_workspace_id and wm.user_id=(select auth.uid()) and wm.status='active' and wm.role='admin') or exists(select 1 from public.workspaces w where w.id=p_workspace_id and w.owner_id=(select auth.uid())) $$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=''
as $$ begin insert into public.profiles(id,full_name) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',split_part(new.email,'@',1))); return new; end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.channels enable row level security;
alter table public.channel_messages enable row level security;
alter table public.message_reactions enable row level security;
alter table public.dm_threads enable row level security;
alter table public.dm_participants enable row level security;
alter table public.dm_messages enable row level security;
alter table public.join_requests enable row level security;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using(true);
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated using((select auth.uid())=id) with check((select auth.uid())=id);

drop policy if exists workspaces_read on public.workspaces;
create policy workspaces_read on public.workspaces for select to authenticated using((select public.is_workspace_member(id)));
drop policy if exists workspace_members_read on public.workspace_members;
create policy workspace_members_read on public.workspace_members for select to authenticated using((select public.is_workspace_member(workspace_id)));
drop policy if exists workspace_members_admin_insert on public.workspace_members;
create policy workspace_members_admin_insert on public.workspace_members for insert to authenticated with check((select public.is_workspace_admin(workspace_id)));
drop policy if exists workspace_members_admin_update on public.workspace_members;
create policy workspace_members_admin_update on public.workspace_members for update to authenticated using((select public.is_workspace_admin(workspace_id))) with check((select public.is_workspace_admin(workspace_id)));

drop policy if exists channels_read on public.channels;
create policy channels_read on public.channels for select to authenticated using((select public.is_workspace_member(workspace_id)));
drop policy if exists channels_admin_insert on public.channels;
create policy channels_admin_insert on public.channels for insert to authenticated with check((select public.is_workspace_admin(workspace_id)));

drop policy if exists channel_messages_read on public.channel_messages;
create policy channel_messages_read on public.channel_messages for select to authenticated using(exists(select 1 from public.channels c where c.id=channel_id and (select public.is_workspace_member(c.workspace_id))));
drop policy if exists channel_messages_insert on public.channel_messages;
create policy channel_messages_insert on public.channel_messages for insert to authenticated with check((select auth.uid())=sender_id and exists(select 1 from public.channels c where c.id=channel_id and (select public.is_workspace_member(c.workspace_id))));

drop policy if exists reactions_read on public.message_reactions;
create policy reactions_read on public.message_reactions for select to authenticated using(exists(select 1 from public.channel_messages m join public.channels c on c.id=m.channel_id where m.id=message_id and (select public.is_workspace_member(c.workspace_id))));
drop policy if exists reactions_insert on public.message_reactions;
create policy reactions_insert on public.message_reactions for insert to authenticated with check((select auth.uid())=user_id);
drop policy if exists reactions_delete on public.message_reactions;
create policy reactions_delete on public.message_reactions for delete to authenticated using((select auth.uid())=user_id);

drop policy if exists dm_threads_read on public.dm_threads;
create policy dm_threads_read on public.dm_threads for select to authenticated using(exists(select 1 from public.dm_participants p where p.thread_id=id and p.user_id=(select auth.uid())));
drop policy if exists dm_threads_insert on public.dm_threads;
create policy dm_threads_insert on public.dm_threads for insert to authenticated with check((select public.is_workspace_member(workspace_id)));
drop policy if exists dm_participants_read on public.dm_participants;
create policy dm_participants_read on public.dm_participants for select to authenticated using(exists(select 1 from public.dm_participants p where p.thread_id=dm_participants.thread_id and p.user_id=(select auth.uid())));
drop policy if exists dm_participants_insert on public.dm_participants;
create policy dm_participants_insert on public.dm_participants for insert to authenticated with check((select auth.uid())=user_id or exists(select 1 from public.dm_participants p where p.thread_id=dm_participants.thread_id and p.user_id=(select auth.uid())));
drop policy if exists dm_messages_read on public.dm_messages;
create policy dm_messages_read on public.dm_messages for select to authenticated using(exists(select 1 from public.dm_participants p where p.thread_id=dm_messages.thread_id and p.user_id=(select auth.uid())));
drop policy if exists dm_messages_insert on public.dm_messages;
create policy dm_messages_insert on public.dm_messages for insert to authenticated with check((select auth.uid())=sender_id and exists(select 1 from public.dm_participants p where p.thread_id=dm_messages.thread_id and p.user_id=(select auth.uid())));

drop policy if exists join_requests_insert on public.join_requests;
create policy join_requests_insert on public.join_requests for insert to authenticated with check((select auth.uid())=user_id);
drop policy if exists join_requests_read on public.join_requests;
create policy join_requests_read on public.join_requests for select to authenticated using((select auth.uid())=user_id or (select public.is_workspace_admin(workspace_id)));
drop policy if exists join_requests_admin_update on public.join_requests;
create policy join_requests_admin_update on public.join_requests for update to authenticated using((select public.is_workspace_admin(workspace_id))) with check((select public.is_workspace_admin(workspace_id)));

alter publication supabase_realtime add table public.channel_messages;
alter publication supabase_realtime add table public.dm_messages;
alter publication supabase_realtime add table public.message_reactions;

create or replace function public.request_workspace_join(workspace_slug text)
returns void language plpgsql security definer set search_path=''
as $
declare wid uuid;
begin
 select id into wid from public.workspaces where slug=workspace_slug;
 if wid is null then raise exception 'Workspace not found'; end if;
 insert into public.join_requests(workspace_id,user_id,email,requested_name)
 select wid,(select auth.uid()),coalesce((select email from auth.users where id=(select auth.uid())),'unknown'),coalesce((select full_name from public.profiles where id=(select auth.uid())),'New member')
 on conflict(workspace_id,user_id) do update set status='pending',requested_name=excluded.requested_name;
end $;
grant execute on function public.request_workspace_join(text) to authenticated;

create or replace function public.get_or_create_dm(p_workspace_id uuid,p_other_user_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $
declare tid uuid;
begin
 if not public.is_workspace_member(p_workspace_id) then raise exception 'Not a workspace member'; end if;
 if not public.is_workspace_member(p_workspace_id) then raise exception 'Invalid workspace'; end if;
 select t.id into tid
 from public.dm_threads t
 where t.workspace_id=p_workspace_id
 and exists(select 1 from public.dm_participants p where p.thread_id=t.id and p.user_id=(select auth.uid()))
 and exists(select 1 from public.dm_participants p where p.thread_id=t.id and p.user_id=p_other_user_id)
 and (select count(*) from public.dm_participants p where p.thread_id=t.id)=2
 limit 1;
 if tid is null then
   insert into public.dm_threads(workspace_id) values(p_workspace_id) returning id into tid;
   insert into public.dm_participants(thread_id,user_id) values(tid,(select auth.uid())),(tid,p_other_user_id);
 end if;
 return tid;
end $;
grant execute on function public.get_or_create_dm(uuid,uuid) to authenticated;

-- Bootstrap after creating the first account:
-- insert into public.workspaces(name,slug,owner_id) values('Bookairfreight HQ','bookairfreight-hq','YOUR_AUTH_USER_UUID');
-- insert into public.workspace_members(workspace_id,user_id,role) select id,'YOUR_AUTH_USER_UUID','admin' from public.workspaces where slug='bookairfreight-hq';
-- insert into public.channels(workspace_id,name,slug,emoji,created_by) select id,'Team HQ','general','👋','YOUR_AUTH_USER_UUID' from public.workspaces where slug='bookairfreight-hq';
-- Add the remaining channels the same way.
