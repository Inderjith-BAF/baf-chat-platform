-- Grant PostgREST table privileges for channel membership management.
-- RLS remains the security boundary; these grants only allow authenticated clients
-- to issue the corresponding SQL operations.
grant select, insert, delete on table public.channel_members to authenticated;