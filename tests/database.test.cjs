const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {PGlite}=require('@electric-sql/pglite');
test('database enforces access, idempotency, cooldown, two terminals and final closure',async()=>{
 const db=new PGlite();
 try{
 await db.exec(`create role anon; create role authenticated; create schema auth;
 create table auth.users(id uuid primary key);
 create function auth.uid() returns uuid language sql as $$ select (current_setting('request.jwt.claims',true)::jsonb->>'sub')::uuid $$;
 create function auth.jwt() returns jsonb language sql as $$ select current_setting('request.jwt.claims',true)::jsonb $$;`);
 await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/schema.sql'),'utf8'));
 const admin='00000000-0000-0000-0000-000000000001',terminal='00000000-0000-0000-0000-000000000002';
 await db.query('insert into auth.users values ($1),($2)',[admin,terminal]);
 await db.query("insert into election_private.operators values ($1,'admin'),($2,'terminal')",[admin,terminal]);
 async function identity(user,session,role='authenticated'){
 await db.exec('reset role');await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,session_id:session})]);await db.exec('set role '+role);
 }
 const s1='10000000-0000-0000-0000-000000000001',s2='10000000-0000-0000-0000-000000000002',s3='10000000-0000-0000-0000-000000000003';
 const r1='20000000-0000-0000-0000-000000000001',r2='20000000-0000-0000-0000-000000000002',r3='20000000-0000-0000-0000-000000000003';
 const call=(name,args=[])=>db.query(`select public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) as result`,args).then(x=>x.rows[0].result);
 await identity(null,null,'anon');
 assert.equal((await call('public_results')).total,0);
 await assert.rejects(call('cast_vote',['A',r1]),/permission denied/);
 await assert.rejects(db.query('select * from election_private.totals'),/permission denied/);
 await identity('00000000-0000-0000-0000-000000000003',s3);
 await assert.rejects(call('activate_terminal'),/não autorizado/);
 await identity(admin,s1);await call('activate_terminal');
 await assert.rejects(call('cast_vote',['A',r1]),/não está aberta/);
 await call('manage_election',['open']);await call('cast_vote',['A',r1]);
 assert.equal((await call('cast_vote',['A',r1])).repeated,true);
 await assert.rejects(call('cast_vote',['B',r2]),/8 segundos/);
 await identity(terminal,s2);await call('activate_terminal');
 await assert.rejects(call('manage_election',['close']),/Somente o administrador/);
 await call('cast_vote',['B',r2]);
 const open=await call('public_results');assert.equal(open.total,2);assert.equal(open.results,null);
 await identity(admin,s3);await assert.rejects(call('activate_terminal'),/dois terminais/);
 await identity(admin,s1);await call('manage_election',['close']);
 await assert.rejects(call('cast_vote',['B',r3]),/não está aberta/);
 assert.equal((await call('cast_vote',['A',r1])).repeated,true);
 await assert.rejects(call('manage_election',['open']),/Ação inválida/);
 await identity(null,null,'anon');const closed=await call('public_results');assert.equal(closed.status,'encerrada');assert.deepEqual(closed.results,{A:1,B:1});
 await assert.rejects(call('manage_election',['delete_apuracao']),/permission denied/);
 await identity(terminal,s2);await assert.rejects(call('manage_election',['delete_apuracao']),/Somente o administrador/);
 await identity(admin,s1);await call('manage_election',['delete_apuracao']);
 const reset=await call('public_results');assert.equal(reset.status,'preparacao');assert.equal(reset.total,0);assert.equal(reset.results,null);
 await db.exec('reset role');
 assert.equal((await db.query('select count(*)::int as n from election_private.receipts')).rows[0].n,0);
 await identity(admin,s1);
 await call('manage_election',['revoke']);
 await assert.rejects(call('cast_vote',['A',r1]),/Terminal não autorizado/);
 }finally{await db.close();}
});
