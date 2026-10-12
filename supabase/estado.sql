-- Estado do solver SBC (clube, cartas, moedas, bloqueadas, historico) por utilizador.
-- Corre isto uma vez no Supabase: SQL Editor -> New query -> Run.

create table if not exists public.estado (
  user_id       uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  chave         text        not null,
  valor         jsonb       not null,
  atualizado_em timestamptz not null default now(),
  primary key (user_id, chave)
);

alter table public.estado enable row level security;

drop policy if exists "estado: ler o proprio"    on public.estado;
drop policy if exists "estado: criar o proprio"  on public.estado;
drop policy if exists "estado: mudar o proprio"  on public.estado;
drop policy if exists "estado: apagar o proprio" on public.estado;

create policy "estado: ler o proprio"    on public.estado for select to authenticated using (auth.uid() = user_id);
create policy "estado: criar o proprio"  on public.estado for insert to authenticated with check (auth.uid() = user_id);
create policy "estado: mudar o proprio"  on public.estado for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "estado: apagar o proprio" on public.estado for delete to authenticated using (auth.uid() = user_id);

-- Sem login (role anon) nao ha nenhuma policy, por isso a tabela devolve vazio.
revoke all on public.estado from anon;
grant select, insert, update, delete on public.estado to authenticated;
