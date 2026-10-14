-- Execute uma vez no SQL Editor de um projeto Supabase novo.
begin;
create schema if not exists election_private;
revoke all on schema election_private from public, anon, authenticated;
create table election_private.operators (
 user_id uuid primary key references auth.users(id),
 role text not null check (role in ('admin','terminal'))
);
create table election_private.election (
 id integer primary key check (id=1),
 status text not null default 'preparacao' check(status in ('preparacao','aberta','encerrada')),
 closed_at timestamptz
);
insert into election_private.election(id) values(1);
create table election_private.totals (choice text primary key check(choice in ('A','B')), votes bigint not null default 0);
insert into election_private.totals(choice) values('A'),('B');
create table election_private.terminals (
 session_id uuid primary key, user_id uuid not null, last_vote timestamptz,
 enabled boolean not null default true
);
-- Recibos de transporte sem a chapa escolhida. Não armazenamos identidade de aluno.
create table election_private.receipts (request_id uuid primary key, session_id uuid not null);
alter table election_private.operators enable row level security;
alter table election_private.election enable row level security;
alter table election_private.totals enable row level security;
alter table election_private.terminals enable row level security;
alter table election_private.receipts enable row level security;

create function public.operator_info() returns jsonb language plpgsql security definer set search_path='' as $$
declare r text;
begin
 select role into r from election_private.operators where user_id=auth.uid();
 if r is null then raise exception 'Acesso não autorizado.'; end if;
 return jsonb_build_object('role',r);
end $$;

create function public.activate_terminal() returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid := (auth.jwt()->>'session_id')::uuid;
begin
 perform public.operator_info();
 if sid is null then raise exception 'Entre novamente.'; end if;
 perform 1 from election_private.election where id=1 for update;
 if exists(select 1 from election_private.terminals where session_id=sid and not enabled) then
 raise exception 'Terminal revogado. Entre novamente.'; end if;
 if not exists(select 1 from election_private.terminals where session_id=sid) then
 if (select count(*) from election_private.terminals where enabled)>=2 then
 raise exception 'Já existem dois terminais. Revogue as sessões no painel administrativo antes de trocar os computadores.'; end if;
 insert into election_private.terminals(session_id,user_id) values(sid,auth.uid());
 end if;
 return jsonb_build_object('ok',true);
end $$;

create function public.cast_vote(p_choice text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid := (auth.jwt()->>'session_id')::uuid; st text; last_at timestamptz;
begin
 perform public.operator_info();
 select status into st from election_private.election where id=1 for update;
 if not exists(select 1 from election_private.terminals where session_id=sid and user_id=auth.uid() and enabled) then raise exception 'Terminal não autorizado.'; end if;
 if exists(select 1 from election_private.receipts where request_id=p_request_id and session_id=sid) then return jsonb_build_object('ok',true,'repeated',true); end if;
 if st <> 'aberta' then raise exception 'A votação não está aberta.'; end if;
 if p_choice is null or p_choice not in ('A','B') or p_request_id is null then raise exception 'Voto inválido.'; end if;
 select last_vote into last_at from election_private.terminals where session_id=sid;
 if last_at is not null and clock_timestamp()<last_at+interval '8 seconds' then raise exception 'Aguarde 8 segundos entre os votos.'; end if;
 insert into election_private.receipts values(p_request_id,sid);
 update election_private.totals set votes=votes+1 where choice=p_choice;
 update election_private.terminals set last_vote=clock_timestamp() where session_id=sid;
 return jsonb_build_object('ok',true,'repeated',false);
end $$;

create function public.public_results() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 -- Uma única consulta usa um único snapshot de status e contagem.
 select jsonb_build_object('status',e.status,'closed_at',e.closed_at,'total',sum(t.votes),
 'results',case when e.status='encerrada' then jsonb_object_agg(t.choice,t.votes) else null end)
 into result from election_private.election e cross join election_private.totals t where e.id=1 group by e.status,e.closed_at;
 return result;
end $$;

create function public.manage_election(p_action text) returns jsonb language plpgsql security definer set search_path='' as $$
declare st text;
begin
 if not exists(select 1 from election_private.operators where user_id=auth.uid() and role='admin') then raise exception 'Somente o administrador pode executar esta ação.'; end if;
 select status into st from election_private.election where id=1 for update;
 if p_action='open' and st='preparacao' then update election_private.election set status='aberta' where id=1;
 elsif p_action='close' and st='aberta' then update election_private.election set status='encerrada',closed_at=clock_timestamp() where id=1;
 elsif p_action='revoke' then update election_private.terminals set enabled=false;
 elsif p_action='delete_apuracao' and st in ('preparacao','aberta','encerrada') then
   delete from election_private.receipts;
   update election_private.totals set votes=0;
   update election_private.terminals set last_vote=null;
   update election_private.election set status='preparacao',closed_at=null where id=1;
 else raise exception 'Ação inválida para o estado atual. Não é possível reabrir uma eleição encerrada.';
 end if;
 return public.public_results();
end $$;

revoke all on function public.operator_info() from public,anon,authenticated;
revoke all on function public.activate_terminal() from public,anon,authenticated;
revoke all on function public.cast_vote(text,uuid) from public,anon,authenticated;
revoke all on function public.manage_election(text) from public,anon,authenticated;
revoke all on function public.public_results() from public,anon,authenticated;
grant execute on function public.operator_info(),public.activate_terminal(),public.cast_vote(text,uuid),public.manage_election(text) to authenticated;
grant execute on function public.public_results() to anon,authenticated;
commit;
