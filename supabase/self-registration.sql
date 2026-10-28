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
