-- Atualização financeira completa: inclui a área do aluno caso ainda não esteja instalada.
begin;
-- Trilha Apostólica — área do aluno.
-- Execute depois das atualizações de perfis/equipe. Preserva os registros atuais.
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

-- Depois de executar: Área do aluno > Atualizar acesso.
-- Crie a conta confirmada do aluno em Authentication > Users.
-- Vincule o e-mail ao cadastro correto em Área do aluno > Vincular conta.
-- Alunos NÃO devem ser inseridos em school_coordinators ou school_team_members.
-- O acesso privado ao endereço do aplicativo é uma autorização separada.
-- Trilha Apostólica — financeiro de alunos.
-- Execute após as atualizações de perfis/equipe e área do aluno.
-- Não altera notas, atividades, presença nem cobranças existentes.
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

-- Depois de executar: Financeiro > Atualizar dados.
-- Cadastre as cobranças e registre os pagamentos na conta da coordenação.
-- Os alunos consultam apenas suas cobranças e não podem registrar pagamentos.
-- Vencimento hoje ainda não é atraso; considera-se o fuso America/Sao_Paulo.
-- Cobranças são individuais e pagamentos são confirmados manualmente, sem gateway.
commit;
