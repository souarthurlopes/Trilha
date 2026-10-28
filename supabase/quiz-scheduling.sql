-- Agendamento de quizzes. Requer o módulo de quizzes já instalado.
-- Horários de São Paulo. Preserva notas e tentativas existentes.
begin;
alter table public.school_quizzes add column if not exists opens_at timestamptz;
alter table public.school_quizzes add column if not exists closes_at timestamptz;
create or replace function public.school_quiz_is_open(quiz public.school_quizzes)
returns boolean language sql stable set search_path='' as $$
 select quiz.published
 and now()>=coalesce(quiz.opens_at,quiz.week_start::timestamp at time zone 'America/Sao_Paulo')
 and now()<coalesce(quiz.closes_at,(quiz.week_start+7)::timestamp at time zone 'America/Sao_Paulo');
$$;
revoke all on function public.school_quiz_is_open(public.school_quizzes) from public,anon;
grant execute on function public.school_quiz_is_open(public.school_quizzes) to authenticated;

grant update(opens_at,closes_at) on public.school_quizzes to authenticated;

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
 if coalesce(new.opens_at,new.week_start::timestamp at time zone 'America/Sao_Paulo')
 >=coalesce(new.closes_at,(new.week_start+7)::timestamp at time zone 'America/Sao_Paulo') then
 raise exception 'O encerramento precisa ser depois da abertura.';end if;
 if (new.opens_at is not null and (new.opens_at<(new.week_start::timestamp at time zone 'America/Sao_Paulo') or new.opens_at>=((new.week_start+7)::timestamp at time zone 'America/Sao_Paulo')))
 or (new.closes_at is not null and (new.closes_at<=(new.week_start::timestamp at time zone 'America/Sao_Paulo') or new.closes_at>((new.week_start+7)::timestamp at time zone 'America/Sao_Paulo'))) then
 raise exception 'A abertura e o encerramento precisam estar dentro da semana do quiz, no horário de São Paulo.';end if;
 new.updated_at:=now();return new;
end;$$;
drop trigger if exists quiz_enforce on public.school_quizzes;
create trigger quiz_enforce before insert or update on public.school_quizzes for each row execute function public.school_quiz_enforce();


create or replace function public.school_my_quizzes(workspace_id uuid)
returns setof jsonb language plpgsql stable security definer set search_path='' as $$
declare student jsonb;
begin
 student:=public.school_quiz_student(workspace_id);if student is null then raise exception 'Acesso de aluno não autorizado.' using errcode='42501';end if;
 return query select jsonb_build_object('id',q.id,'title',q.title,'description',q.description,'class_id',q.class_id,'week_start',q.week_start,'question_count',jsonb_array_length(q.questions),
  'opens_at',coalesce(q.opens_at,q.week_start::timestamp at time zone 'America/Sao_Paulo'),'closes_at',coalesce(q.closes_at,(q.week_start+7)::timestamp at time zone 'America/Sao_Paulo'),
  'availability',case when not q.published then 'closed' when now()<coalesce(q.opens_at,q.week_start::timestamp at time zone 'America/Sao_Paulo') then 'scheduled' when public.school_quiz_is_open(q) then 'open' else 'closed' end,
  'can_submit',public.school_quiz_is_open(q) and q.week_start=public.school_quiz_week() and q.class_id=student->>'class_id' and a.id is null,
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
 if not coordinator and (student is null or (attempt.id is null and (not quiz.published or quiz.published_at is null or quiz.week_start>public.school_quiz_week() or now()<coalesce(quiz.opens_at,quiz.week_start::timestamp at time zone 'America/Sao_Paulo') or quiz.class_id<>student->>'class_id'))) then raise exception 'Você não tem acesso a este quiz.' using errcode='42501';end if;
 select jsonb_agg(case when attempt.id is null and not coordinator then jsonb_build_object('id',q->>'id','prompt',q->>'prompt','options',(select jsonb_agg(jsonb_build_object('id',o->>'id','text',o->>'text')) from jsonb_array_elements(q->'options') o)) else q end) into safe_questions from jsonb_array_elements(quiz.questions) q;
 return jsonb_build_object('id',quiz.id,'title',quiz.title,'description',quiz.description,'week_start',quiz.week_start,'questions',safe_questions,
  'opens_at',coalesce(quiz.opens_at,quiz.week_start::timestamp at time zone 'America/Sao_Paulo'),'closes_at',coalesce(quiz.closes_at,(quiz.week_start+7)::timestamp at time zone 'America/Sao_Paulo'),
  'can_submit',not coordinator and attempt.id is null and public.school_quiz_is_open(quiz) and quiz.week_start=public.school_quiz_week() and quiz.class_id=student->>'class_id',
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
 if not public.school_quiz_is_open(quiz) or quiz.published_at is null or quiz.week_start<>public.school_quiz_week() or quiz.class_id<>student->>'class_id' then raise exception 'Este quiz não está aberto para sua turma neste horário ou nesta semana.';end if;
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


commit;
