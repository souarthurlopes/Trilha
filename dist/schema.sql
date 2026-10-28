-- Trilha Apostólica — primeira versão, acesso exclusivo da coordenação.
-- Execute no SQL Editor de um projeto Supabase NOVO.
-- Nenhuma senha nem chave secreta é necessária no aplicativo.
begin;
create table if not exists public.school_coordinators (
 user_id uuid primary key references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
alter table public.school_coordinators enable row level security;
revoke all on public.school_coordinators from anon, authenticated;
grant select on public.school_coordinators to authenticated;
drop policy if exists coordinator_self_read on public.school_coordinators;
create policy coordinator_self_read on public.school_coordinators for select to authenticated using (user_id = (select auth.uid()));

create or replace function public.valid_school_workspace(doc jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
declare k text; item jsonb; keys text[]; grade_keys text[]; attendance_keys text[];
begin
 if jsonb_typeof(doc) <> 'object' or octet_length(doc::text) > 5000000 then return false; end if;
 foreach k in array array['classes','students','assessments','grades','attendance','notices'] loop
  if not (doc ? k) or jsonb_typeof(doc->k) <> 'array' then return false; end if;
 end loop;
 foreach k in array array['classes','students','assessments','notices'] loop
  keys := array[]::text[];
  for item in select value from jsonb_array_elements(doc->k) loop
   if jsonb_typeof(item)<>'object' or jsonb_typeof(item->'id') is distinct from 'string' or length(item->>'id') not between 1 and 100 or (item->>'id')=any(keys) then return false; end if;
   keys := array_append(keys,item->>'id');
   if k in ('classes','students') then
    if jsonb_typeof(item->'name') is distinct from 'string' or length(btrim(item->>'name')) not between 1 and 120 then return false; end if;
   else
    if jsonb_typeof(item->'title') is distinct from 'string' or length(btrim(item->>'title')) not between 1 and 100 then return false; end if;
    if (item->>'date') is null or (item->>'date') !~ '^\d{4}-\d{2}-\d{2}$' then return false; end if;
    perform (item->>'date')::date;
   end if;
   if k in ('students','assessments') and not exists (select 1 from jsonb_array_elements(doc->'classes') c where c->>'id'=item->>'classId') then return false; end if;
   if k='notices' and (jsonb_typeof(item->'body') is distinct from 'string' or length(item->>'body') not between 1 and 5000) then return false; end if;
  end loop;
 end loop;
 grade_keys := array[]::text[];
 for item in select value from jsonb_array_elements(doc->'grades') loop
  if jsonb_typeof(item->'value') is distinct from 'number' or (item->>'value')::numeric not between 0 and 10 then return false; end if;
  if not exists (select 1 from jsonb_array_elements(doc->'students') s where s->>'id'=item->>'studentId') or not exists (select 1 from jsonb_array_elements(doc->'assessments') a where a->>'id'=item->>'assessmentId') then return false; end if;
  k := (item->>'studentId') || ':' || (item->>'assessmentId');
  if k=any(grade_keys) then return false; end if;
  grade_keys := array_append(grade_keys,k);
 end loop;
 attendance_keys := array[]::text[];
 for item in select value from jsonb_array_elements(doc->'attendance') loop
  if (item->>'status') is null or (item->>'status') not in ('present','absent','excused') or (item->>'date') is null or (item->>'date') !~ '^\d{4}-\d{2}-\d{2}$' then return false; end if;
  perform (item->>'date')::date;
  if not exists (select 1 from jsonb_array_elements(doc->'students') s where s->>'id'=item->>'studentId') or not exists (select 1 from jsonb_array_elements(doc->'classes') c where c->>'id'=item->>'classId') then return false; end if;
  k := (item->>'studentId') || ':' || (item->>'classId') || ':' || (item->>'date');
  if k=any(attendance_keys) then return false; end if;
  attendance_keys := array_append(attendance_keys,k);
 end loop;
 return true;
exception when others then return false;
end;
$$;

create table if not exists public.school_workspaces (
 owner_id uuid primary key references auth.users(id) on delete cascade,
 data jsonb not null default '{"classes":[],"students":[],"assessments":[],"grades":[],"attendance":[],"notices":[]}'::jsonb,
 revision bigint not null default 1 check (revision > 0),
 updated_at timestamptz not null default now(),
 constraint valid_school_data check (public.valid_school_workspace(data))
);
alter table public.school_workspaces enable row level security;
revoke all on public.school_workspaces from anon, authenticated;
grant select, insert on public.school_workspaces to authenticated;
grant update (data, revision, updated_at) on public.school_workspaces to authenticated;

drop policy if exists workspace_read on public.school_workspaces;
create policy workspace_read on public.school_workspaces for select to authenticated
 using (owner_id=(select auth.uid()) and exists(select 1 from public.school_coordinators where user_id=(select auth.uid())));
drop policy if exists workspace_insert on public.school_workspaces;
create policy workspace_insert on public.school_workspaces for insert to authenticated
 with check (owner_id=(select auth.uid()) and revision=1 and exists(select 1 from public.school_coordinators where user_id=(select auth.uid())));
drop policy if exists workspace_update on public.school_workspaces;
create policy workspace_update on public.school_workspaces for update to authenticated
 using (owner_id=(select auth.uid()) and exists(select 1 from public.school_coordinators where user_id=(select auth.uid())))
 with check (owner_id=(select auth.uid()) and exists(select 1 from public.school_coordinators where user_id=(select auth.uid())));

create or replace function public.advance_school_revision()
returns trigger language plpgsql set search_path = '' as $$
begin
 if new.owner_id <> old.owner_id or new.revision <> old.revision+1 then
  raise exception 'Revisão inválida: recarregue os dados antes de salvar.';
 end if;
 new.updated_at := now();
 return new;
end;
$$;
drop trigger if exists school_revision_check on public.school_workspaces;
create trigger school_revision_check before update on public.school_workspaces for each row execute function public.advance_school_revision();
commit;

-- PRÓXIMO PASSO, depois de executar o esquema:
-- 1. Authentication > Users > Add user: crie o coordenador e confirme o e-mail.
-- 2. Copie o User UID e execute esta linha substituindo o exemplo:
-- insert into public.school_coordinators(user_id) values ('COLE-O-UUID-DO-USUARIO-AQUI');
-- 3. Desative novos cadastros nas configurações de Authentication.
-- 4. Configure URL + chave PUBLISHABLE ou ANON no aplicativo.
-- 5. Entre com o e-mail e a senha do coordenador.
-- Uma conta não autorizada e visitantes anônimos não podem ler nem gravar dados.
-- O acesso de professores/alunos exige nova modelagem e políticas próprias.
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
-- Trilha Apostólica — área do aluno.
-- Execute depois das atualizações de perfis/equipe. Preserva os registros atuais.
begin;
create table if not exists public.school_student_accounts (
 workspace_owner_id uuid not null references public.school_workspaces(owner_id) on delete cascade,
 student_id text not null,
 user_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(workspace_owner_id,user_id),
 unique(workspace_owner_id,student_id)
);
create index if not exists student_accounts_by_user on public.school_student_accounts(user_id);
alter table public.school_student_accounts enable row level security;
revoke all on public.school_student_accounts from anon, authenticated;
grant select on public.school_student_accounts to authenticated;
drop policy if exists student_accounts_read on public.school_student_accounts;
create policy student_accounts_read on public.school_student_accounts for select to authenticated
 using(user_id=(select auth.uid()) or public.school_can_access(workspace_owner_id));

create or replace function public.school_student_class(workspace_id uuid)
returns text language sql stable security definer set search_path='' as $$
 select s->>'classId' from public.school_student_accounts a
 join public.school_workspaces w on w.owner_id=a.workspace_owner_id
 cross join lateral jsonb_array_elements(w.data->'students') s
 where a.workspace_owner_id=workspace_id and a.user_id=auth.uid() and s->>'id'=a.student_id;
$$;
revoke all on function public.school_student_class(uuid) from public,anon;
grant execute on function public.school_student_class(uuid) to authenticated;

create table if not exists public.school_learning_items (
 id uuid primary key default gen_random_uuid(),
 workspace_owner_id uuid not null references public.school_workspaces(owner_id) on delete cascade,
 class_id text not null,
 kind text not null check(kind in ('material','activity')),
 title text not null check(char_length(btrim(title)) between 1 and 120),
 body text not null default '' check(char_length(body)<=10000),
 resource_url text not null default '' check(resource_url='' or (char_length(resource_url)<=2000 and resource_url ~ '^https://')),
 due_date date,
 published boolean not null default false,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(id,workspace_owner_id)
);
create index if not exists learning_items_by_workspace on public.school_learning_items(workspace_owner_id,class_id);
alter table public.school_learning_items enable row level security;
revoke all on public.school_learning_items from anon,authenticated;
grant select,insert,delete on public.school_learning_items to authenticated;
grant update(class_id,kind,title,body,resource_url,due_date,published,updated_at) on public.school_learning_items to authenticated;
drop policy if exists learning_items_read on public.school_learning_items;
create policy learning_items_read on public.school_learning_items for select to authenticated
 using(public.school_can_access(workspace_owner_id) or (published and class_id=public.school_student_class(workspace_owner_id)));
drop policy if exists learning_items_insert on public.school_learning_items;
create policy learning_items_insert on public.school_learning_items for insert to authenticated
 with check(public.school_can_access(workspace_owner_id));
drop policy if exists learning_items_update on public.school_learning_items;
create policy learning_items_update on public.school_learning_items for update to authenticated
 using(public.school_can_access(workspace_owner_id)) with check(public.school_can_access(workspace_owner_id));
drop policy if exists learning_items_delete on public.school_learning_items;
create policy learning_items_delete on public.school_learning_items for delete to authenticated
 using(public.school_can_access(workspace_owner_id));

create table if not exists public.school_learning_submissions (
 item_id uuid not null,
 workspace_owner_id uuid not null,
 student_user_id uuid not null references auth.users(id) on delete cascade,
 student_id text not null,
 response text not null default '' check(char_length(response)<=10000),
 completed boolean not null default true,
 updated_at timestamptz not null default now(),
 primary key(item_id,student_user_id),
 foreign key(item_id,workspace_owner_id) references public.school_learning_items(id,workspace_owner_id) on delete cascade
);
alter table public.school_learning_submissions enable row level security;
revoke all on public.school_learning_submissions from anon,authenticated;
grant select,insert on public.school_learning_submissions to authenticated;
grant update(response,completed,updated_at) on public.school_learning_submissions to authenticated;

create or replace function public.school_can_submit(workspace_id uuid,learning_id uuid,student_record_id text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.school_learning_items i
  join public.school_student_accounts a on a.workspace_owner_id=i.workspace_owner_id
  where i.id=learning_id and i.workspace_owner_id=workspace_id
   and i.kind='activity' and i.published
   and a.user_id=auth.uid() and a.student_id=student_record_id
   and i.class_id=public.school_student_class(workspace_id)
 );
$$;
revoke all on function public.school_can_submit(uuid,uuid,text) from public,anon;
grant execute on function public.school_can_submit(uuid,uuid,text) to authenticated;
drop policy if exists submissions_read on public.school_learning_submissions;
create policy submissions_read on public.school_learning_submissions for select to authenticated
 using(public.school_can_access(workspace_owner_id) or (student_user_id=(select auth.uid()) and public.school_can_submit(workspace_owner_id,item_id,student_id)));
drop policy if exists submissions_insert on public.school_learning_submissions;
create policy submissions_insert on public.school_learning_submissions for insert to authenticated
 with check(student_user_id=(select auth.uid()) and public.school_can_submit(workspace_owner_id,item_id,student_id));
drop policy if exists submissions_update on public.school_learning_submissions;
create policy submissions_update on public.school_learning_submissions for update to authenticated
 using(student_user_id=(select auth.uid()) and public.school_can_submit(workspace_owner_id,item_id,student_id))
 with check(student_user_id=(select auth.uid()) and public.school_can_submit(workspace_owner_id,item_id,student_id));

create or replace function public.school_student_links(workspace_id uuid)
returns table(student_id text,user_id uuid,email text)
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.school_can_access(workspace_id) then raise exception 'Acesso restrito à coordenação.' using errcode='42501'; end if;
 return query select a.student_id,a.user_id,u.email::text
 from public.school_student_accounts a join auth.users u on u.id=a.user_id
 where a.workspace_owner_id=workspace_id;
end;
$$;
revoke all on function public.school_student_links(uuid) from public,anon;
grant execute on function public.school_student_links(uuid) to authenticated;

create or replace function public.school_link_student(workspace_id uuid,student_record_id text,student_email text)
returns void language plpgsql security definer set search_path='' as $$
declare account_id uuid;
begin
 if not public.school_can_access(workspace_id) then raise exception 'Acesso restrito à coordenação.' using errcode='42501'; end if;
 -- Serializa alterações de vínculo desta escola.
 perform 1 from public.school_workspaces where owner_id=workspace_id for update;
 if not exists(select 1 from public.school_workspaces w cross join lateral jsonb_array_elements(w.data->'students') s where w.owner_id=workspace_id and s->>'id'=student_record_id)
 then raise exception 'Aluno não encontrado nesta escola.'; end if;
 select u.id into account_id from auth.users u where lower(u.email)=lower(btrim(student_email)) and u.email_confirmed_at is not null;
 if account_id is null then raise exception 'Crie e confirme a conta do aluno em Authentication > Users antes de vinculá-la.'; end if;
 if account_id=workspace_id or exists(select 1 from public.school_team_members m where m.workspace_owner_id=workspace_id and m.user_id=account_id)
 then raise exception 'Use uma conta individual de aluno, diferente da conta de coordenação.'; end if;
 if exists(select 1 from public.school_student_accounts a where a.workspace_owner_id=workspace_id and a.user_id=account_id and a.student_id<>student_record_id)
 then raise exception 'Essa conta já está vinculada a outro aluno desta escola.'; end if;
 insert into public.school_student_accounts(workspace_owner_id,student_id,user_id)
 values(workspace_id,student_record_id,account_id)
 on conflict(workspace_owner_id,student_id) do update set user_id=excluded.user_id;
end;
$$;
revoke all on function public.school_link_student(uuid,text,text) from public,anon;
grant execute on function public.school_link_student(uuid,text,text) to authenticated;

create or replace function public.school_unlink_student(workspace_id uuid,student_record_id text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.school_can_access(workspace_id) then raise exception 'Acesso restrito à coordenação.' using errcode='42501'; end if;
 delete from public.school_student_accounts a where a.workspace_owner_id=workspace_id and a.student_id=student_record_id;
end;
$$;
revoke all on function public.school_unlink_student(uuid,text) from public,anon;
grant execute on function public.school_unlink_student(uuid,text) to authenticated;

create or replace function public.school_student_portals()
returns setof jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'owner_id',w.owner_id,
  'student',jsonb_build_object('id',s->>'id','name',s->>'name','classId',s->>'classId'),
  'class_name',coalesce((select c->>'name' from jsonb_array_elements(w.data->'classes') c where c->>'id'=s->>'classId'),'Turma'),
  'assessments',coalesce((select jsonb_agg(e) from jsonb_array_elements(w.data->'assessments') e where e->>'classId'=s->>'classId' or exists(select 1 from jsonb_array_elements(w.data->'grades') g where g->>'studentId'=a.student_id and g->>'assessmentId'=e->>'id')),'[]'::jsonb),
  'grades',coalesce((select jsonb_agg(g) from jsonb_array_elements(w.data->'grades') g where g->>'studentId'=a.student_id),'[]'::jsonb),
  'attendance',coalesce((select jsonb_agg(t) from jsonb_array_elements(w.data->'attendance') t where t->>'studentId'=a.student_id),'[]'::jsonb),
  'notices',w.data->'notices',
  'learning_items',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from public.school_learning_items i where i.workspace_owner_id=w.owner_id and i.class_id=s->>'classId' and i.published),'[]'::jsonb),
  'submissions',coalesce((select jsonb_agg(to_jsonb(r)) from public.school_learning_submissions r join public.school_learning_items i on i.id=r.item_id where r.workspace_owner_id=w.owner_id and r.student_user_id=auth.uid() and r.student_id=a.student_id and i.class_id=s->>'classId' and i.published),'[]'::jsonb)
 )
 from public.school_student_accounts a
 join public.school_workspaces w on w.owner_id=a.workspace_owner_id
 cross join lateral jsonb_array_elements(w.data->'students') s
 where a.user_id=auth.uid() and s->>'id'=a.student_id;
$$;
revoke all on function public.school_student_portals() from public,anon;
grant execute on function public.school_student_portals() to authenticated;
commit;

-- Depois de executar: Área do aluno > Atualizar acesso.
-- Crie a conta confirmada do aluno em Authentication > Users.
-- Vincule o e-mail ao cadastro correto em Área do aluno > Vincular conta.
-- Alunos NÃO devem ser inseridos em school_coordinators ou school_team_members.
-- O acesso privado ao endereço do aplicativo é uma autorização separada.
-- Trilha Apostólica — financeiro de alunos.
-- Execute após as atualizações de perfis/equipe e área do aluno.
-- Não altera notas, atividades, presença nem cobranças existentes.
begin;
create table if not exists public.school_finance_charges (
 id uuid primary key default gen_random_uuid(),
 workspace_owner_id uuid not null references public.school_workspaces(owner_id) on delete cascade,
 student_id text not null,
 student_name text not null default '',
 description text not null check(char_length(btrim(description)) between 1 and 160),
 amount_cents integer not null check(amount_cents between 1 and 999999999),
 due_date date not null,
 state text not null default 'open' check(state in ('open','paid','canceled')),
 paid_on date,
 payment_method text check(payment_method in ('pix','cash','transfer','card','other')),
 row_version bigint not null default 1 check(row_version>0),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check((state='paid' and paid_on is not null and payment_method is not null) or (state<>'paid' and paid_on is null and payment_method is null))
);
create index if not exists finance_charges_by_student on public.school_finance_charges(workspace_owner_id,student_id,due_date);
alter table public.school_finance_charges enable row level security;
revoke all on public.school_finance_charges from anon,authenticated;
grant select,insert on public.school_finance_charges to authenticated;
grant update(description,amount_cents,due_date,state,paid_on,payment_method,row_version) on public.school_finance_charges to authenticated;
drop policy if exists finance_read on public.school_finance_charges;
create policy finance_read on public.school_finance_charges for select to authenticated
 using(public.school_can_access(workspace_owner_id) or (
  public.school_student_class(workspace_owner_id) is not null and exists(
   select 1 from public.school_student_accounts a where a.workspace_owner_id=school_finance_charges.workspace_owner_id
   and a.student_id=school_finance_charges.student_id and a.user_id=(select auth.uid())
  )
 ));
drop policy if exists finance_insert on public.school_finance_charges;
create policy finance_insert on public.school_finance_charges for insert to authenticated
 with check(public.school_can_access(workspace_owner_id) and state='open' and row_version=1);
drop policy if exists finance_update on public.school_finance_charges;
create policy finance_update on public.school_finance_charges for update to authenticated
 using(public.school_can_access(workspace_owner_id)) with check(public.school_can_access(workspace_owner_id));

create table if not exists public.school_finance_audit (
 id bigint generated always as identity primary key,
 workspace_owner_id uuid not null references public.school_workspaces(owner_id) on delete cascade,
 charge_id uuid not null references public.school_finance_charges(id) on delete cascade,
 actor_id uuid references auth.users(id) on delete set null,
 operation text not null check(operation in ('INSERT','UPDATE')),
 previous_data jsonb,
 current_data jsonb not null,
 changed_at timestamptz not null default now()
);
alter table public.school_finance_audit enable row level security;
revoke all on public.school_finance_audit from anon,authenticated;
grant select on public.school_finance_audit to authenticated;
drop policy if exists finance_audit_read on public.school_finance_audit;
create policy finance_audit_read on public.school_finance_audit for select to authenticated using(public.school_can_access(workspace_owner_id));

create or replace function public.school_finance_enforce()
returns trigger language plpgsql security definer set search_path='' as $$
declare roster_name text; business_today date := (now() at time zone 'America/Sao_Paulo')::date;
begin
 if auth.uid() is not null and not public.school_can_access(new.workspace_owner_id) then
  raise exception 'Somente a coordenação pode alterar cobranças.' using errcode='42501';
 end if;
 if tg_op='INSERT' then
  if new.state<>'open' or new.row_version<>1 then raise exception 'Crie uma cobrança em aberto antes de registrar o pagamento.'; end if;
  select s->>'name' into roster_name from public.school_workspaces w
   cross join lateral jsonb_array_elements(w.data->'students') s
   where w.owner_id=new.workspace_owner_id and s->>'id'=new.student_id;
  if roster_name is null then raise exception 'Aluno não encontrado nesta escola.'; end if;
  new.student_name:=roster_name;new.created_at:=now();
 else
  if new.id<>old.id or new.workspace_owner_id<>old.workspace_owner_id or new.student_id<>old.student_id
   or new.student_name<>old.student_name or new.created_at<>old.created_at then
   raise exception 'A identificação da cobrança não pode ser alterada.';
  end if;
  if new.row_version<>old.row_version+1 then raise exception 'Registro desatualizado. Atualize os dados antes de salvar.'; end if;
  if old.state='canceled' then raise exception 'Cobranças canceladas são preservadas no histórico e não podem ser alteradas.'; end if;
  if old.state='paid' and new.state<>'open' then raise exception 'Para corrigir um pagamento, primeiro reabra a cobrança.'; end if;
  if old.state='paid' or new.state in ('paid','canceled') then
   if new.description<>old.description or new.amount_cents<>old.amount_cents or new.due_date<>old.due_date then
    raise exception 'Altere os dados da cobrança separadamente do registro de pagamento ou cancelamento.';
   end if;
  end if;
 end if;
 if new.state='paid' and new.paid_on>business_today then raise exception 'A data do pagamento não pode estar no futuro.'; end if;
 new.updated_at:=now();return new;
end;
$$;
drop trigger if exists finance_enforce on public.school_finance_charges;
create trigger finance_enforce before insert or update on public.school_finance_charges for each row execute function public.school_finance_enforce();

create or replace function public.school_finance_record_audit()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.school_finance_audit(workspace_owner_id,charge_id,actor_id,operation,previous_data,current_data)
 values(new.workspace_owner_id,new.id,auth.uid(),tg_op,case when tg_op='UPDATE' then to_jsonb(old) else null end,to_jsonb(new));
 return new;
end;
$$;
drop trigger if exists finance_audit on public.school_finance_charges;
create trigger finance_audit after insert or update on public.school_finance_charges for each row execute function public.school_finance_record_audit();
commit;

-- Depois de executar: Financeiro > Atualizar dados.
-- Cadastre as cobranças e registre os pagamentos na conta da coordenação.
-- Os alunos consultam apenas suas cobranças e não podem registrar pagamentos.
-- Vencimento hoje ainda não é atraso; considera-se o fuso America/Sao_Paulo.
-- Cobranças são individuais e pagamentos são confirmados manualmente, sem gateway.
-- Trilha Apostólica — cadastro de alunos com aprovação no aplicativo.
-- Execute depois de perfis/equipe e área do aluno. Preserva os registros atuais.
begin;
create table if not exists public.school_registration_settings (
 workspace_owner_id uuid primary key references public.school_workspaces(owner_id) on delete cascade,
 enabled boolean not null default true
);
alter table public.school_registration_settings enable row level security;
revoke all on public.school_registration_settings from anon,authenticated;
grant select on public.school_registration_settings to authenticated;
drop policy if exists registration_settings_read on public.school_registration_settings;
create policy registration_settings_read on public.school_registration_settings for select to authenticated using(public.school_can_access(workspace_owner_id));
insert into public.school_registration_settings(workspace_owner_id)
 select w.owner_id from public.school_workspaces w join public.school_coordinators c on c.user_id=w.owner_id on conflict do nothing;

create table if not exists public.school_registration_requests (
 id uuid primary key default gen_random_uuid(),
 workspace_owner_id uuid not null references public.school_workspaces(owner_id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 full_name text not null check(char_length(btrim(full_name)) between 1 and 120),
 state text not null default 'pending' check(state in ('pending','approved','declined')),
 student_id text,
 decided_by uuid references auth.users(id) on delete set null,
 decided_at timestamptz,
 created_at timestamptz not null default now(),
 unique(workspace_owner_id,user_id)
);
alter table public.school_registration_requests enable row level security;
revoke all on public.school_registration_requests from anon,authenticated;
grant select on public.school_registration_requests to authenticated;
drop policy if exists registration_requests_read on public.school_registration_requests;
create policy registration_requests_read on public.school_registration_requests for select to authenticated
 using(user_id=(select auth.uid()) or public.school_can_access(workspace_owner_id));

create or replace function public.school_registration_target(requested_workspace uuid default null)
returns uuid language sql stable security definer set search_path='' as $$
 select case when requested_workspace is not null then
  (select r.workspace_owner_id from public.school_registration_settings r where r.workspace_owner_id=requested_workspace and r.enabled)
 else
  (select case when count(*)=1 then (array_agg(r.workspace_owner_id))[1] else null end from public.school_registration_settings r where r.enabled)
 end;
$$;
revoke all on function public.school_registration_target(uuid) from public;
grant execute on function public.school_registration_target(uuid) to anon,authenticated;

create or replace function public.school_enable_registration(workspace_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is distinct from workspace_id or not public.school_can_access(workspace_id) then
  raise exception 'Somente o responsável principal pode ativar o cadastro.' using errcode='42501';
 end if;
 insert into public.school_registration_settings(workspace_owner_id,enabled) values(workspace_id,true)
 on conflict(workspace_owner_id) do update set enabled=true;
end;
$$;
revoke all on function public.school_enable_registration(uuid) from public,anon;
grant execute on function public.school_enable_registration(uuid) to authenticated;

create or replace function public.school_submit_registration(requested_name text,requested_workspace uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare target uuid;request public.school_registration_requests;name_value text;
begin
 if auth.uid() is null or not exists(select 1 from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null) then
  raise exception 'Confirme seu e-mail e entre na sua conta antes de solicitar acesso.' using errcode='42501';
 end if;
 target:=public.school_registration_target(requested_workspace);
 if target is null then raise exception 'Peça à coordenação o link de cadastro desta Trilha.'; end if;
 if public.school_can_access(target) then raise exception 'Sua conta já pertence à coordenação.'; end if;
 name_value:=btrim(requested_name);
 if name_value is null or char_length(name_value) not between 1 and 120 then raise exception 'Informe seu nome completo.'; end if;
 insert into public.school_registration_requests(workspace_owner_id,user_id,full_name)
 values(target,auth.uid(),name_value)
 on conflict(workspace_owner_id,user_id) do nothing;
 select r.* into request from public.school_registration_requests r where r.workspace_owner_id=target and r.user_id=auth.uid();
 return jsonb_build_object('id',request.id,'state',request.state,'full_name',request.full_name,'workspace_owner_id',request.workspace_owner_id,'created_at',request.created_at);
end;
$$;
revoke all on function public.school_submit_registration(text,uuid) from public,anon;
grant execute on function public.school_submit_registration(text,uuid) to authenticated;

create or replace function public.school_registration_queue(workspace_id uuid)
returns table(id uuid,full_name text,email text,state text,student_id text,created_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.school_can_access(workspace_id) then raise exception 'Acesso restrito à coordenação.' using errcode='42501'; end if;
 return query select r.id,r.full_name,u.email::text,r.state,r.student_id,r.created_at
 from public.school_registration_requests r join auth.users u on u.id=r.user_id
 where r.workspace_owner_id=workspace_id order by r.created_at desc;
end;
$$;
revoke all on function public.school_registration_queue(uuid) from public,anon;
grant execute on function public.school_registration_queue(uuid) to authenticated;

create or replace function public.school_review_registration(request_id uuid,accept_request boolean,student_record_id text default null)
returns void language plpgsql security definer set search_path='' as $$
declare request public.school_registration_requests;verified_email text;
begin
 select r.* into request from public.school_registration_requests r where r.id=request_id;
 if not found or not public.school_can_access(request.workspace_owner_id) then raise exception 'Acesso restrito à coordenação.' using errcode='42501'; end if;
 -- Usa a mesma ordem de bloqueio da vinculação de alunos.
 perform 1 from public.school_workspaces w where w.owner_id=request.workspace_owner_id for update;
 select r.* into request from public.school_registration_requests r where r.id=request_id for update;
 if request.state<>'pending' then raise exception 'Esta solicitação já foi analisada. Atualize a lista.'; end if;
 if accept_request then
  if student_record_id is null then raise exception 'Selecione o cadastro do aluno.'; end if;
  if exists(select 1 from public.school_student_accounts a where a.workspace_owner_id=request.workspace_owner_id and a.student_id=student_record_id and a.user_id<>request.user_id)
  then raise exception 'Este aluno já possui outra conta vinculada. Confira o cadastro antes de trocar o acesso.'; end if;
  select u.email into verified_email from auth.users u where u.id=request.user_id and u.email_confirmed_at is not null;
  if verified_email is null then raise exception 'A conta ainda não tem e-mail confirmado.'; end if;
  perform public.school_link_student(request.workspace_owner_id,student_record_id,verified_email);
 end if;
 update public.school_registration_requests r set state=case when accept_request then 'approved' else 'declined' end,
  student_id=case when accept_request then student_record_id else null end,decided_by=auth.uid(),decided_at=now()
 where r.id=request_id;
end;
$$;
revoke all on function public.school_review_registration(uuid,boolean,text) from public,anon;
grant execute on function public.school_review_registration(uuid,boolean,text) to authenticated;
commit;

-- Uma vez no painel Supabase:
-- Authentication > Sign In / Providers: habilite novos cadastros e confirmação de e-mail.
-- Authentication > URL Configuration: use a URL do app no Cloudflare em Site URL e Redirect URLs.
-- Depois: Área do aluno > Atualizar acesso > Solicitações de cadastro.
-- Os participantes criam a própria conta e você aprova pelo aplicativo.
-- Cadastros novos não recebem acesso à coordenação nem aos registros dos alunos antes da aprovação.
-- Trilha Apostólica — quizzes nativos e ranking semanal por turma.
-- Requer perfis/equipe e área do aluno. Não altera as notas das avaliações.
begin;
create or replace function public.school_quiz_week(day_date date default (now() at time zone 'America/Sao_Paulo')::date)
returns date language sql stable set search_path='' as $$select day_date-(extract(isodow from day_date)::integer-1);$$;
revoke all on function public.school_quiz_week(date) from public,anon;
grant execute on function public.school_quiz_week(date) to authenticated;

create or replace function public.school_valid_quiz_questions(items jsonb)
returns boolean language plpgsql immutable set search_path='' as $$
declare q jsonb;o jsonb;qids text[]:=array[]::text[];oids text[];
begin
 if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items) not between 1 and 50 or octet_length(items::text)>1000000 then return false;end if;
 for q in select value from jsonb_array_elements(items) loop
  if jsonb_typeof(q->'id') is distinct from 'string' or length(q->>'id') not between 1 and 100 or q->>'id'=any(qids) then return false;end if;qids:=array_append(qids,q->>'id');
  if jsonb_typeof(q->'prompt') is distinct from 'string' or length(btrim(q->>'prompt')) not between 1 and 2000 then return false;end if;
  if jsonb_typeof(q->'options') is distinct from 'array' or jsonb_array_length(q->'options') not between 2 and 6 then return false;end if;
  oids:=array[]::text[];
  for o in select value from jsonb_array_elements(q->'options') loop
   if jsonb_typeof(o->'id') is distinct from 'string' or length(o->>'id') not between 1 and 100 or o->>'id'=any(oids) or jsonb_typeof(o->'text') is distinct from 'string' or length(btrim(o->>'text')) not between 1 and 1000 then return false;end if;
   oids:=array_append(oids,o->>'id');
  end loop;
  if jsonb_typeof(q->'correct_option_id') is distinct from 'string' or not(q->>'correct_option_id'=any(oids)) then return false;end if;
  if q ? 'explanation' and (jsonb_typeof(q->'explanation') is distinct from 'string' or length(q->>'explanation')>3000) then return false;end if;
 end loop;return true;
exception when others then return false;
end;$$;
create table if not exists public.school_quizzes (
 id uuid primary key default gen_random_uuid(),
 workspace_owner_id uuid not null references public.school_workspaces(owner_id) on delete cascade,
 class_id text not null,
 title text not null check(length(btrim(title)) between 1 and 120),
 description text not null default '' check(length(description)<=5000),
 week_start date not null default public.school_quiz_week() check(extract(isodow from week_start)=1),
 questions jsonb not null check(public.school_valid_quiz_questions(questions)),
 published boolean not null default false,
 published_at timestamptz,
 row_version bigint not null default 1 check(row_version>0),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(id,workspace_owner_id)
);
create index if not exists quizzes_by_class_week on public.school_quizzes(workspace_owner_id,class_id,week_start);
alter table public.school_quizzes enable row level security;
revoke all on public.school_quizzes from anon,authenticated;
grant select,insert,delete on public.school_quizzes to authenticated;
grant update(title,description,class_id,week_start,questions,published,row_version) on public.school_quizzes to authenticated;
drop policy if exists quizzes_coordinator_read on public.school_quizzes;
create policy quizzes_coordinator_read on public.school_quizzes for select to authenticated using(public.school_can_access(workspace_owner_id));
drop policy if exists quizzes_coordinator_insert on public.school_quizzes;
create policy quizzes_coordinator_insert on public.school_quizzes for insert to authenticated with check(public.school_can_access(workspace_owner_id));
drop policy if exists quizzes_coordinator_update on public.school_quizzes;
create policy quizzes_coordinator_update on public.school_quizzes for update to authenticated using(public.school_can_access(workspace_owner_id)) with check(public.school_can_access(workspace_owner_id));
drop policy if exists quizzes_draft_delete on public.school_quizzes;
create policy quizzes_draft_delete on public.school_quizzes for delete to authenticated using(public.school_can_access(workspace_owner_id) and published_at is null);

create or replace function public.school_quiz_enforce()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is not null and not public.school_can_access(new.workspace_owner_id) then raise exception 'Somente a coordenação pode criar quizzes.' using errcode='42501';end if;
 if tg_op='UPDATE' then
  if new.id<>old.id or new.workspace_owner_id<>old.workspace_owner_id then raise exception 'A identificação do quiz não pode ser alterada.';end if;
  if new.row_version<>old.row_version+1 then raise exception 'O quiz foi alterado em outra janela. Atualize antes de salvar.';end if;
  if old.published_at is not null and (new.questions<>old.questions or new.class_id<>old.class_id or new.week_start<>old.week_start) then raise exception 'As questões, a turma e a semana de um quiz já publicado não podem ser alteradas. Crie uma cópia.';end if;
  new.published_at:=old.published_at;
 else new.row_version:=1;new.created_at:=now();new.published_at:=null;end if;
 if not exists(select 1 from public.school_workspaces w cross join lateral jsonb_array_elements(w.data->'classes') c where w.owner_id=new.workspace_owner_id and c->>'id'=new.class_id) then raise exception 'Selecione uma turma válida.';end if;
 if new.published and new.published_at is null then new.published_at:=now();end if;
 new.updated_at:=now();return new;
end;$$;
drop trigger if exists quiz_enforce on public.school_quizzes;
create trigger quiz_enforce before insert or update on public.school_quizzes for each row execute function public.school_quiz_enforce();

create table if not exists public.school_quiz_attempts (
 id uuid primary key default gen_random_uuid(),
 quiz_id uuid not null,
 workspace_owner_id uuid not null,
 student_id text not null,
 student_user_id uuid references auth.users(id) on delete set null,
 class_id text not null,
 answers jsonb not null,
 correct_count integer not null check(correct_count>=0),
 question_count integer not null check(question_count between 1 and 50 and correct_count<=question_count),
 submitted_at timestamptz not null default now(),
 unique(quiz_id,student_id),
 foreign key(quiz_id,workspace_owner_id) references public.school_quizzes(id,workspace_owner_id) on delete restrict
);
create index if not exists quiz_attempts_by_student on public.school_quiz_attempts(workspace_owner_id,student_id);
alter table public.school_quiz_attempts enable row level security;
revoke all on public.school_quiz_attempts from anon,authenticated;
grant select on public.school_quiz_attempts to authenticated;
drop policy if exists quiz_attempts_coordinator_read on public.school_quiz_attempts;
create policy quiz_attempts_coordinator_read on public.school_quiz_attempts for select to authenticated using(public.school_can_access(workspace_owner_id));

create or replace function public.school_quiz_student(workspace_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',s->>'id','name',s->>'name','class_id',s->>'classId')
 from public.school_student_accounts a join public.school_workspaces w on w.owner_id=a.workspace_owner_id
 cross join lateral jsonb_array_elements(w.data->'students') s
 where a.workspace_owner_id=workspace_id and a.user_id=auth.uid() and s->>'id'=a.student_id;
$$;
revoke all on function public.school_quiz_student(uuid) from public,anon;
grant execute on function public.school_quiz_student(uuid) to authenticated;

create or replace function public.school_my_quizzes(workspace_id uuid)
returns setof jsonb language plpgsql stable security definer set search_path='' as $$
declare student jsonb;
begin
 student:=public.school_quiz_student(workspace_id);if student is null then raise exception 'Acesso de aluno não autorizado.' using errcode='42501';end if;
 return query select jsonb_build_object('id',q.id,'title',q.title,'description',q.description,'class_id',q.class_id,'week_start',q.week_start,'question_count',jsonb_array_length(q.questions),
  'can_submit',q.published and q.week_start=public.school_quiz_week() and q.class_id=student->>'class_id' and a.id is null,
  'result',case when a.id is null then null else jsonb_build_object('correct_count',a.correct_count,'question_count',a.question_count,'submitted_at',a.submitted_at) end)
 from public.school_quizzes q left join public.school_quiz_attempts a on a.quiz_id=q.id and a.student_id=student->>'id'
 where q.workspace_owner_id=workspace_id and ((q.published and q.published_at is not null and q.week_start<=public.school_quiz_week() and q.class_id=student->>'class_id') or a.id is not null)
 order by q.week_start desc,q.created_at desc;
end;$$;
revoke all on function public.school_my_quizzes(uuid) from public,anon;
grant execute on function public.school_my_quizzes(uuid) to authenticated;

create or replace function public.school_get_quiz(quiz_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare quiz public.school_quizzes;student jsonb;attempt public.school_quiz_attempts;safe_questions jsonb;coordinator boolean;
begin
 select q.* into quiz from public.school_quizzes q where q.id=quiz_id;
 if not found then raise exception 'Quiz não encontrado.';end if;
 coordinator:=public.school_can_access(quiz.workspace_owner_id);student:=public.school_quiz_student(quiz.workspace_owner_id);
 if student is not null then select a.* into attempt from public.school_quiz_attempts a where a.quiz_id=quiz.id and a.student_id=student->>'id';end if;
 if not coordinator and (student is null or (attempt.id is null and (not quiz.published or quiz.published_at is null or quiz.week_start>public.school_quiz_week() or quiz.class_id<>student->>'class_id'))) then raise exception 'Você não tem acesso a este quiz.' using errcode='42501';end if;
 select jsonb_agg(case when attempt.id is null and not coordinator then jsonb_build_object('id',q->>'id','prompt',q->>'prompt','options',(select jsonb_agg(jsonb_build_object('id',o->>'id','text',o->>'text')) from jsonb_array_elements(q->'options') o)) else q end) into safe_questions from jsonb_array_elements(quiz.questions) q;
 return jsonb_build_object('id',quiz.id,'title',quiz.title,'description',quiz.description,'week_start',quiz.week_start,'questions',safe_questions,
  'can_submit',not coordinator and attempt.id is null and quiz.published and quiz.week_start=public.school_quiz_week() and quiz.class_id=student->>'class_id',
  'result',case when attempt.id is null then null else jsonb_build_object('correct_count',attempt.correct_count,'question_count',attempt.question_count,'submitted_at',attempt.submitted_at,'answers',attempt.answers) end);
end;$$;
revoke all on function public.school_get_quiz(uuid) from public,anon;
grant execute on function public.school_get_quiz(uuid) to authenticated;

create or replace function public.school_submit_quiz(quiz_id uuid,submitted_answers jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare quiz public.school_quizzes;student jsonb;existing public.school_quiz_attempts;q jsonb;correct integer:=0;answer_count integer;
begin
 select qz.* into quiz from public.school_quizzes qz where qz.id=quiz_id for update;
 if not found then raise exception 'Quiz não encontrado.';end if;
 student:=public.school_quiz_student(quiz.workspace_owner_id);if student is null then raise exception 'Acesso de aluno não autorizado.' using errcode='42501';end if;
 select a.* into existing from public.school_quiz_attempts a where a.quiz_id=quiz.id and a.student_id=student->>'id';
 if existing.id is not null then return public.school_get_quiz(quiz.id);end if;
 if not quiz.published or quiz.published_at is null or quiz.week_start<>public.school_quiz_week() or quiz.class_id<>student->>'class_id' then raise exception 'Este quiz não está aberto para sua turma nesta semana.';end if;
 if jsonb_typeof(submitted_answers) is distinct from 'object' then raise exception 'Responda todas as questões antes de finalizar.';end if;
 select count(*) into answer_count from jsonb_object_keys(submitted_answers);
 if answer_count<>jsonb_array_length(quiz.questions) then raise exception 'Responda todas as questões antes de finalizar.';end if;
 for q in select value from jsonb_array_elements(quiz.questions) loop
  if jsonb_typeof(submitted_answers->(q->>'id')) is distinct from 'string' or not exists(select 1 from jsonb_array_elements(q->'options') o where o->>'id'=submitted_answers->>(q->>'id')) then raise exception 'Responda cada questão com uma alternativa válida.';end if;
  if submitted_answers->>(q->>'id')=q->>'correct_option_id' then correct:=correct+1;end if;
 end loop;
 insert into public.school_quiz_attempts(quiz_id,workspace_owner_id,student_id,student_user_id,class_id,answers,correct_count,question_count)
 values(quiz.id,quiz.workspace_owner_id,student->>'id',auth.uid(),student->>'class_id',submitted_answers,correct,jsonb_array_length(quiz.questions));
 return public.school_get_quiz(quiz.id);
end;$$;
revoke all on function public.school_submit_quiz(uuid,jsonb) from public,anon;
grant execute on function public.school_submit_quiz(uuid,jsonb) to authenticated;

create or replace function public.school_weekly_quiz_ranking(workspace_id uuid,requested_week date default null,requested_class text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare student jsonb;class_value text;week_value date;entries jsonb;
begin
 student:=public.school_quiz_student(workspace_id);week_value:=public.school_quiz_week(coalesce(requested_week,public.school_quiz_week()));
 if public.school_can_access(workspace_id) then class_value:=requested_class;
 elsif student is not null then
  class_value:=student->>'class_id';if requested_class is not null and requested_class<>class_value then raise exception 'O ranking é restrito à sua turma.' using errcode='42501';end if;
  if week_value>public.school_quiz_week() then raise exception 'O ranking desta semana ainda não começou.';end if;
 else raise exception 'Acesso não autorizado ao ranking.' using errcode='42501';end if;
 if class_value is null or not exists(select 1 from public.school_workspaces w cross join lateral jsonb_array_elements(w.data->'classes') c where w.owner_id=workspace_id and c->>'id'=class_value) then raise exception 'Selecione uma turma válida.';end if;
 with scores as (
  select s->>'id' as student_id,s->>'name' as full_name,sum(a.correct_count)::integer as correct_count,sum(a.question_count)::integer as question_count,count(*)::integer as quiz_count
  from public.school_quiz_attempts a join public.school_quizzes q on q.id=a.quiz_id
  join public.school_workspaces w on w.owner_id=a.workspace_owner_id
  cross join lateral jsonb_array_elements(w.data->'students') s
  where a.workspace_owner_id=workspace_id and q.week_start=week_value and q.published_at is not null
   and s->>'id'=a.student_id and s->>'classId'=class_value and a.class_id=class_value
   and exists(select 1 from public.school_student_accounts link where link.workspace_owner_id=workspace_id and link.student_id=a.student_id)
  group by s->>'id',s->>'name'
 ), ranked as (select *,rank() over(order by correct_count desc) as position from scores)
 select coalesce(jsonb_agg(jsonb_build_object('position',r.position,'name',r.full_name,'correct_count',r.correct_count,'question_count',r.question_count,'quiz_count',r.quiz_count,'is_me',coalesce(r.student_id=student->>'id',false)) order by r.correct_count desc,r.full_name),'[]'::jsonb) into entries from ranked r;
 return jsonb_build_object('week_start',week_value,'week_end',week_value+6,'class_id',class_value,'entries',entries);
end;$$;
revoke all on function public.school_weekly_quiz_ranking(uuid,date,text) from public,anon;
grant execute on function public.school_weekly_quiz_ranking(uuid,date,text) to authenticated;
commit;

-- Depois de executar: Quizzes > Atualizar dados.
-- A coordenação cria as questões e publica o quiz para uma turma e uma semana.
-- Ranking de segunda a domingo, no fuso America/Sao_Paulo, separado por turma.
-- Só a primeira tentativa finalizada conta; empates mantêm a mesma posição.
-- Gabaritos não são enviados ao aluno antes da finalização.
-- Quizzes e ranking não alteram a média das avaliações.
