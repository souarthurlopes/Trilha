-- Aulas gravadas e anotações privadas. Requer perfis/equipe e área do aluno.
begin;
create table if not exists public.school_recorded_lessons (
 id uuid primary key default gen_random_uuid(),
 workspace_owner_id uuid not null references public.school_workspaces(owner_id) on delete cascade,
 class_id text not null,title text not null check(length(btrim(title)) between 1 and 120),
 description text not null default '' check(length(description)<=10000),
 youtube_id text not null check(youtube_id ~ '^[A-Za-z0-9_-]{11}$'),
 lesson_date date not null default (now() at time zone 'America/Sao_Paulo')::date,
 resource_url text not null default '' check(resource_url='' or (length(resource_url)<=2000 and resource_url ~ '^https://')),
 published boolean not null default false,published_at timestamptz,row_version integer not null default 1,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(id,workspace_owner_id)
);
create index if not exists recorded_lessons_by_class on public.school_recorded_lessons(workspace_owner_id,class_id,lesson_date desc);
alter table public.school_recorded_lessons enable row level security;
revoke all on public.school_recorded_lessons from anon,authenticated;
grant select,insert on public.school_recorded_lessons to authenticated;
grant update(class_id,title,description,youtube_id,lesson_date,resource_url,published,row_version) on public.school_recorded_lessons to authenticated;
drop policy if exists recorded_lessons_read on public.school_recorded_lessons;
create policy recorded_lessons_read on public.school_recorded_lessons for select to authenticated
 using(public.school_can_access(workspace_owner_id) or (published and class_id=public.school_student_class(workspace_owner_id)));
drop policy if exists recorded_lessons_insert on public.school_recorded_lessons;
create policy recorded_lessons_insert on public.school_recorded_lessons for insert to authenticated with check(public.school_can_access(workspace_owner_id));
drop policy if exists recorded_lessons_update on public.school_recorded_lessons;
create policy recorded_lessons_update on public.school_recorded_lessons for update to authenticated using(public.school_can_access(workspace_owner_id)) with check(public.school_can_access(workspace_owner_id));
create or replace function public.school_recorded_lesson_enforce()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not public.school_can_access(new.workspace_owner_id) then raise exception 'Somente a coordenação pode publicar aulas.' using errcode='42501';end if;
 if tg_op='UPDATE' then
  if new.id<>old.id or new.workspace_owner_id<>old.workspace_owner_id then raise exception 'A identificação da aula não pode mudar.';end if;
  if old.published_at is not null and (new.youtube_id<>old.youtube_id or new.class_id<>old.class_id) then raise exception 'O vídeo e a turma de uma aula já publicada não podem mudar. Cadastre uma nova aula.';end if;
  new.published_at:=old.published_at;
  if new.row_version<>old.row_version+1 then raise exception 'A aula foi alterada em outra janela. Atualize antes de salvar.';end if;
 else new.row_version:=1;new.created_at:=now();new.published_at:=null;end if;
 if new.published and new.published_at is null then new.published_at:=now();end if;
 if not exists(select 1 from public.school_workspaces w cross join lateral jsonb_array_elements(w.data->'classes') c where w.owner_id=new.workspace_owner_id and c->>'id'=new.class_id) then raise exception 'Selecione uma turma válida.';end if;
 new.updated_at:=now();return new;
end;$$;
drop trigger if exists recorded_lesson_enforce on public.school_recorded_lessons;
create trigger recorded_lesson_enforce before insert or update on public.school_recorded_lessons for each row execute function public.school_recorded_lesson_enforce();
create or replace function public.school_can_watch_lesson(workspace_id uuid,lesson_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.school_recorded_lessons l where l.id=lesson_id and l.workspace_owner_id=workspace_id and l.published and l.class_id=public.school_student_class(workspace_id));
$$;
revoke all on function public.school_can_watch_lesson(uuid,uuid) from public,anon;
grant execute on function public.school_can_watch_lesson(uuid,uuid) to authenticated;
create table if not exists public.school_lesson_notes (
 lesson_id uuid not null,workspace_owner_id uuid not null,
 user_id uuid not null references auth.users(id) on delete cascade,
 notes text not null default '' check(length(notes)<=30000),completed boolean not null default false,
 revision integer not null default 1 check(revision>0),updated_at timestamptz not null default now(),
 primary key(lesson_id,user_id),foreign key(lesson_id,workspace_owner_id) references public.school_recorded_lessons(id,workspace_owner_id) on delete cascade
);
alter table public.school_lesson_notes enable row level security;
revoke all on public.school_lesson_notes from anon,authenticated;
grant select on public.school_lesson_notes to authenticated;
drop policy if exists lesson_notes_private_read on public.school_lesson_notes;
create policy lesson_notes_private_read on public.school_lesson_notes for select to authenticated
 using(user_id=(select auth.uid()) and public.school_can_watch_lesson(workspace_owner_id,lesson_id));
create or replace function public.school_save_lesson_note(lesson_id uuid,expected_revision integer,note_text text,is_completed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare lesson public.school_recorded_lessons;saved public.school_lesson_notes;
begin
 select l.* into lesson from public.school_recorded_lessons l where l.id=lesson_id for share;
 if not found or auth.uid() is null or not public.school_can_watch_lesson(lesson.workspace_owner_id,lesson.id) then raise exception 'Acesso à aula não autorizado.' using errcode='42501';end if;
 if note_text is null or length(note_text)>30000 or is_completed is null or expected_revision is null or expected_revision<0 then raise exception 'Anotação inválida (limite de 30.000 caracteres).';end if;
 if expected_revision=0 then
  insert into public.school_lesson_notes(lesson_id,workspace_owner_id,user_id,notes,completed) values(lesson.id,lesson.workspace_owner_id,auth.uid(),note_text,is_completed) on conflict do nothing returning * into saved;
 else
  update public.school_lesson_notes n set notes=note_text,completed=is_completed,revision=n.revision+1,updated_at=now()
  where n.lesson_id=lesson.id and n.user_id=auth.uid() and n.revision=expected_revision returning n.* into saved;
 end if;
 if saved.lesson_id is null then raise exception 'Esta anotação foi alterada em outra janela. Copie seu texto e reabra a aula antes de salvar.' using errcode='40001';end if;
 return jsonb_build_object('lesson_id',saved.lesson_id,'notes',saved.notes,'completed',saved.completed,'revision',saved.revision,'updated_at',saved.updated_at);
end;$$;
revoke all on function public.school_save_lesson_note(uuid,integer,text,boolean) from public,anon;
grant execute on function public.school_save_lesson_note(uuid,integer,text,boolean) to authenticated;
commit;
