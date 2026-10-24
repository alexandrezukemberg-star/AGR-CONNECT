-- Execute no SQL Editor de um projeto Supabase exclusivo do AGR CONNECT.
-- Configure em Authentication > Providers > Email a confirmação por e-mail.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9_]{3,25}$'),
  display_name text not null check (char_length(display_name) between 1 and 70),
  created_at timestamptz not null default now()
);
create table if not exists public.direct_messages (
  id bigint generated always as identity primary key,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now(),
  check (sender_id <> recipient_id)
);
create index if not exists dm_sender_date on public.direct_messages(sender_id,created_at desc);
create index if not exists dm_recipient_date on public.direct_messages(recipient_id,created_at desc);
alter table public.profiles enable row level security;
alter table public.direct_messages enable row level security;
create policy "signed in profiles lookup" on public.profiles for select to authenticated using (true);
create policy "profile owner edit" on public.profiles for update to authenticated using ((select auth.uid())=id) with check ((select auth.uid())=id);
create policy "messages only participants read" on public.direct_messages for select to authenticated using ((select auth.uid())=sender_id or (select auth.uid())=recipient_id);
create policy "messages only sender inserts" on public.direct_messages for insert to authenticated with check ((select auth.uid())=sender_id);
-- Cadastro de perfil seguro: trigger executado após o registro Auth.
create or replace function public.create_agr_profile() returns trigger language plpgsql security definer set search_path = '' as $$
declare u text; n text;
begin
  u := lower(coalesce(new.raw_user_meta_data->>'username',''));
  n := trim(coalesce(new.raw_user_meta_data->>'display_name',''));
  if u !~ '^[a-z0-9_]{3,25}$' or char_length(n) not between 1 and 70 then
    raise exception 'Nome ou usuario invalido';
  end if;
  insert into public.profiles(id,username,display_name) values(new.id,u,n);
  return new;
end; $$;
revoke all on function public.create_agr_profile() from public, anon, authenticated;
drop trigger if exists on_agr_user_created on auth.users;
create trigger on_agr_user_created after insert on auth.users for each row execute function public.create_agr_profile();
-- Realtime: publique a tabela de mensagens para receber eventos INSERT.
do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='direct_messages') then
  alter publication supabase_realtime add table public.direct_messages;
 end if;
end $$;
