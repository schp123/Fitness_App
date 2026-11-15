-- Forma – Cloud-Backup der Trainingsdaten
-- Supabase: SQL Editor → New query → alles einfügen → Run.
-- Jede Zeile gehört genau einem Account (auth.uid()); niemand sonst kann sie lesen.

create table if not exists public.fitness_records (
  user_id    uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  kind       text        not null,
  id         uuid        not null,
  data       jsonb       not null,
  deleted    boolean     not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create index if not exists fitness_records_user_updated on public.fitness_records (user_id, updated_at);

alter table public.fitness_records enable row level security;

drop policy if exists "own read"   on public.fitness_records;
drop policy if exists "own insert" on public.fitness_records;
drop policy if exists "own update" on public.fitness_records;

create policy "own read"   on public.fitness_records for select to authenticated using (user_id = auth.uid());
create policy "own insert" on public.fitness_records for insert to authenticated with check (user_id = auth.uid());
create policy "own update" on public.fitness_records for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke all on public.fitness_records from anon;
grant select, insert, update on public.fitness_records to authenticated;

create or replace function public.fitness_touch() returns trigger
language plpgsql as $$
begin
  new.updated_at = clock_timestamp();
  return new;
end $$;

drop trigger if exists fitness_records_touch on public.fitness_records;
create trigger fitness_records_touch before insert or update on public.fitness_records
  for each row execute function public.fitness_touch();
