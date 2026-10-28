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
