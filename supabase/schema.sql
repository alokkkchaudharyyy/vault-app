-- Run once in the Supabase SQL editor. Safe to run again.
--
-- Mirrors the local SQLite tables. `user_id` scopes every row to the signed-in
-- user; `server_at` is the pull cursor; timestamps written by the apps are
-- fixed-width UTC strings, so comparing them as text is correct.

create or replace function todo_stamp() returns trigger language plpgsql set search_path = '' as $$
begin
  -- Last write wins: drop an update that is older than the stored row.
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null;
  end if;
  new.server_at := clock_timestamp();
  return new;
end $$;

-- The diary was first released as "briefs": carry an existing table over.
do $$
begin
  if to_regclass('public.briefs') is not null and to_regclass('public.diary') is null then
    alter table briefs rename to diary;
    alter index if exists briefs_pull rename to diary_pull;
  end if;
end $$;

do $$
declare
  t text;
  extra text;
begin
  for t, extra in values
    ('lists', 'title text not null'),
    ('tasks', 'list_id text, title text not null, notes text, tag text, date text,
               start_time text, end_time text, done_at text, calendar_event_id text,
               due_date text, estimate_min integer, protect text, source_entry text, history text'),
    ('habits', 'title text not null, time text, start_date text, end_date text, sort integer not null default 0'),
    ('habit_checks', 'habit_id text not null, date text not null, done integer not null'),
    ('focus_sessions', 'task_id text, kind text not null, started_at text not null,
                        planned_min integer not null, ended_at text'),
    ('screen_usage', 'device_id text not null, device text not null, app text not null, name text not null,
                      date text not null, hour integer not null, seconds integer not null'),
    ('diary', 'date text not null, author text not null, body text not null,
               task_id text, habit_id text, filed_at text, outcome text'),
    ('pages', 'kind text not null, key text not null, title text, body text not null'),
    ('expenses', 'at text not null, date text not null, amount bigint not null, direction text not null,
                  merchant text, category text, account text, source text, note text'),
    ('health', 'date text not null, kind text not null, value double precision, detail text')
  loop
    execute format('create table if not exists %I (
      id text primary key,
      user_id uuid not null default auth.uid() references auth.users on delete cascade,
      %s,
      created_at text not null,
      updated_at text not null,
      deleted_at text,
      server_at timestamptz not null default clock_timestamp()
    )', t, extra);
    execute format('create index if not exists %I on %I (user_id, server_at)', t || '_pull', t);
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists own_rows on %I', t);
    execute format('create policy own_rows on %I for all to authenticated
      using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
    execute format('drop trigger if exists stamp on %I', t);
    execute format('create trigger stamp before insert or update on %I
      for each row execute function todo_stamp()', t);
  end loop;
end $$;

-- Added after the first release.
alter table habits add column if not exists time text;
alter table diary add column if not exists task_id text;
alter table diary add column if not exists habit_id text;
alter table diary add column if not exists filed_at text;
alter table tasks add column if not exists due_date text;
alter table tasks add column if not exists estimate_min integer;
alter table tasks add column if not exists protect text;
alter table tasks add column if not exists source_entry text;
alter table tasks add column if not exists history text;
alter table diary add column if not exists outcome text;
