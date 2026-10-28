-- Trilha Apostólica — perfis e coordenação compartilhada.
-- Execute após o schema.sql original. Preserva alunos, notas e presença.
begin;

create table if not exists public.school_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null default '' check (char_length(display_name) <= 120),
 phone text not null default '' check (char_length(phone) <= 30),
 responsibility text not null default '' check (char_length(responsibility) <= 120),
 avatar_data text not null default '' check (
  avatar_data = '' or (
   char_length(avatar_data) <= 160000 and
   avatar_data ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$'
  )
 ),
 updated_at timestamptz not null default now()
);
alter table public.school_profiles enable row level security;
revoke all on public.school_profiles from anon, authenticated;
grant select, insert on public.school_profiles to authenticated;
grant update(display_name, phone, responsibility, avatar_data, updated_at)
 on public.school_profiles to authenticated;
drop policy if exists profile_self_read on public.school_profiles;
create policy profile_self_read on public.school_profiles for select to authenticated
 using (user_id=(select auth.uid()));
drop policy if exists profile_self_insert on public.school_profiles;
create policy profile_self_insert on public.school_profiles for insert to authenticated
 with check (user_id=(select auth.uid()));
drop policy if exists profile_self_update on public.school_profiles;
create policy profile_self_update on public.school_profiles for update to authenticated
 using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));

create table if not exists public.school_team_members (
 workspace_owner_id uuid not null references public.school_workspaces(owner_id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(workspace_owner_id,user_id),
 check (workspace_owner_id <> user_id)
);
create index if not exists school_team_by_user on public.school_team_members(user_id);
alter table public.school_team_members enable row level security;
revoke all on public.school_team_members from anon, authenticated;
grant select on public.school_team_members to authenticated;
drop policy if exists team_self_read on public.school_team_members;
create policy team_self_read on public.school_team_members for select to authenticated
 using (user_id=(select auth.uid()) or workspace_owner_id=(select auth.uid()));

create or replace function public.school_can_access(workspace_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
 select (workspace_id=auth.uid() and exists(
  select 1 from public.school_coordinators c where c.user_id=auth.uid()
 )) or exists(
  select 1 from public.school_team_members m
  where m.workspace_owner_id=workspace_id and m.user_id=auth.uid()
 );
$$;
revoke all on function public.school_can_access(uuid) from public, anon;
grant execute on function public.school_can_access(uuid) to authenticated;

drop policy if exists workspace_read on public.school_workspaces;
create policy workspace_read on public.school_workspaces for select to authenticated
 using (public.school_can_access(owner_id));
drop policy if exists workspace_update on public.school_workspaces;
create policy workspace_update on public.school_workspaces for update to authenticated
 using (public.school_can_access(owner_id)) with check (public.school_can_access(owner_id));
-- A política de criação permanece exclusiva dos coordenadores autorizados.

create or replace function public.school_access_context()
returns table(workspace_owner_id uuid, owner_name text, is_owner boolean)
language sql stable security definer set search_path = '' as $$
 select c.user_id,
  coalesce(nullif(p.display_name,''),nullif(u.raw_user_meta_data->>'full_name',''),u.email,'Coordenação'),
  true
 from public.school_coordinators c
 join auth.users u on u.id=c.user_id
 left join public.school_profiles p on p.user_id=c.user_id
 where c.user_id=auth.uid()
 union all
 select m.workspace_owner_id,
  coalesce(nullif(p.display_name,''),nullif(u.raw_user_meta_data->>'full_name',''),u.email,'Coordenação'),
  false
 from public.school_team_members m
 join auth.users u on u.id=m.workspace_owner_id
 left join public.school_profiles p on p.user_id=m.workspace_owner_id
 where m.user_id=auth.uid();
$$;
revoke all on function public.school_access_context() from public, anon;
grant execute on function public.school_access_context() to authenticated;

create or replace function public.school_team_directory(workspace_id uuid)
returns table(user_id uuid, display_name text, email text, member_role text, joined_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
 if not public.school_can_access(workspace_id) then
  raise exception 'Você não tem acesso a esta equipe.' using errcode='42501';
 end if;
 return query
 select u.id, coalesce(nullif(p.display_name,''),nullif(u.raw_user_meta_data->>'full_name',''),'Coordenação'),
  u.email::text, 'owner'::text, c.created_at
 from public.school_coordinators c
 join auth.users u on u.id=c.user_id
 left join public.school_profiles p on p.user_id=u.id
 where c.user_id=workspace_id
 union all
 select u.id, coalesce(nullif(p.display_name,''),nullif(u.raw_user_meta_data->>'full_name',''),'Coordenação'),
  u.email::text, 'coordinator'::text, m.created_at
 from public.school_team_members m
 join auth.users u on u.id=m.user_id
 left join public.school_profiles p on p.user_id=u.id
 where m.workspace_owner_id=workspace_id;
end;
$$;
revoke all on function public.school_team_directory(uuid) from public, anon;
grant execute on function public.school_team_directory(uuid) to authenticated;

create or replace function public.school_add_coordinator(workspace_id uuid, member_email text)
returns void language plpgsql security definer set search_path = '' as $$
declare member_id uuid;
begin
 if workspace_id is distinct from auth.uid() or not exists(
  select 1 from public.school_coordinators c where c.user_id=auth.uid()
 ) or not exists(
  select 1 from public.school_workspaces w where w.owner_id=workspace_id
 ) then
  raise exception 'Somente o responsável principal pode gerenciar a equipe.' using errcode='42501';
 end if;
 select u.id into member_id from auth.users u
 where lower(u.email)=lower(btrim(member_email)) and u.email_confirmed_at is not null;
 if member_id is null then
  raise exception 'Conta não encontrada ou e-mail não confirmado. Crie o usuário em Authentication > Users no Supabase e confirme o e-mail.';
 end if;
 if member_id=workspace_id then raise exception 'Você já é o responsável principal.'; end if;
 insert into public.school_team_members(workspace_owner_id,user_id)
 values(workspace_id,member_id) on conflict do nothing;
end;
$$;
revoke all on function public.school_add_coordinator(uuid,text) from public, anon;
grant execute on function public.school_add_coordinator(uuid,text) to authenticated;

create or replace function public.school_remove_coordinator(workspace_id uuid, member_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if workspace_id is distinct from auth.uid() or not exists(
  select 1 from public.school_coordinators c where c.user_id=auth.uid()
 ) then
  raise exception 'Somente o responsável principal pode gerenciar a equipe.' using errcode='42501';
 end if;
 delete from public.school_team_members m
 where m.workspace_owner_id=workspace_id and m.user_id=member_id;
end;
$$;
revoke all on function public.school_remove_coordinator(uuid,uuid) from public, anon;
grant execute on function public.school_remove_coordinator(uuid,uuid) to authenticated;
commit;

-- Depois de executar, volte à aba Perfil e clique em Atualizar acesso.
-- Para adicionar alguém: crie a conta confirmada em Authentication > Users.
-- No aplicativo, Perfil > Equipe de coordenação > Adicionar coordenador.
-- Não inclua os membros em school_coordinators: eles usam os dados da equipe.
-- O acesso privado ao endereço do aplicativo também precisa ser liberado.
