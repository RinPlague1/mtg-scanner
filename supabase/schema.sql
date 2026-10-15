-- MTG Binder (working title) — Supabase schema
-- Paste this whole file into Supabase → SQL Editor → New query → Run.
-- Safe to re-run: tables use IF NOT EXISTS and functions use CREATE OR REPLACE.


-- ───────────────────────── Tables ─────────────────────────

create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  username     text not null unique check (username ~ '^[a-z0-9_]{3,20}$'),
  display_name text,
  share_token  uuid not null unique default gen_random_uuid(),
  created_at   timestamptz not null default now()
);

-- Full collection backup (synced from the phone, which is the source of truth).
create table if not exists public.collection_items (
  user_id   uuid not null references auth.users(id) on delete cascade,
  item_key  text not null,
  card      jsonb not null,           -- Scryfall printing snapshot (name, set, image, prices)
  name_key  text not null,            -- normalised card name, used for matching
  foil      boolean not null default false,
  qty       int not null check (qty > 0),
  binder    text not null default 'collection' check (binder in ('collection', 'showcase', 'trade')),
  condition text not null default 'NM',
  added     timestamptz not null default now(),
  primary key (user_id, item_key)
);
create index if not exists collection_items_binder on public.collection_items (user_id, binder);

create table if not exists public.decks (
  user_id uuid not null references auth.users(id) on delete cascade,
  id      text not null,
  data    jsonb not null,             -- name, commander, status, cards
  primary key (user_id, id)
);

-- Things only the owner sees.
create table if not exists public.private_state (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  wishlist       jsonb not null default '[]',
  applied_trades jsonb not null default '[]',
  updated_at     timestamptz not null default now()
);

-- Spares and wants, computed on the phone and published for friends.
create table if not exists public.public_lists (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  spares     jsonb not null default '[]',
  wants      jsonb not null default '[]',
  updated_at timestamptz not null default now()
);

create table if not exists public.friendships (
  user_a       uuid not null references auth.users(id) on delete cascade,
  user_b       uuid not null references auth.users(id) on delete cascade,
  status       text not null check (status in ('pending', 'accepted')),
  requested_by uuid not null,
  created_at   timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);

create table if not exists public.trades (
  id         uuid primary key default gen_random_uuid(),
  from_user  uuid not null references auth.users(id) on delete cascade,
  to_user    uuid not null references auth.users(id) on delete cascade,
  status     text not null default 'proposed'
             check (status in ('proposed', 'accepted', 'declined', 'cancelled', 'countered', 'completed')),
  give       jsonb not null default '[]',  -- cards from_user gives
  receive    jsonb not null default '[]',  -- cards to_user gives
  message    text,
  from_done  boolean not null default false,
  to_done    boolean not null default false,
  parent_id  uuid references public.trades(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists trades_from on public.trades (from_user);
create index if not exists trades_to on public.trades (to_user);

-- ───────────────────────── Helpers ─────────────────────────

create or replace function public.are_friends(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from friendships
    where user_a = least(a, b) and user_b = greatest(a, b) and status = 'accepted'
  );
$$;

-- New sign-ups get a profile from the username passed at sign-up.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, username, display_name)
  values (
    new.id,
    lower(new.raw_user_meta_data ->> 'username'),
    coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'username')
  );
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ───────────────────────── Row Level Security ─────────────────────────

alter table public.profiles         enable row level security;
alter table public.collection_items enable row level security;
alter table public.decks            enable row level security;
alter table public.private_state    enable row level security;
alter table public.public_lists     enable row level security;
alter table public.friendships      enable row level security;
alter table public.trades           enable row level security;

drop policy if exists "profiles readable by signed-in users" on public.profiles;
create policy "profiles readable by signed-in users" on public.profiles
  for select to authenticated using (true);
drop policy if exists "own profile editable" on public.profiles;
create policy "own profile editable" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "own collection" on public.collection_items;
create policy "own collection" on public.collection_items
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "friends see showcase and trade binders" on public.collection_items;
create policy "friends see showcase and trade binders" on public.collection_items
  for select to authenticated
  using (binder in ('showcase', 'trade') and public.are_friends(auth.uid(), user_id));

drop policy if exists "own decks" on public.decks;
create policy "own decks" on public.decks
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "own private state" on public.private_state;
create policy "own private state" on public.private_state
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "own lists" on public.public_lists;
create policy "own lists" on public.public_lists
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "friends see lists" on public.public_lists;
create policy "friends see lists" on public.public_lists
  for select to authenticated using (public.are_friends(auth.uid(), user_id));

-- Friendships and trades are only changed through the functions below.
drop policy if exists "see own friendships" on public.friendships;
create policy "see own friendships" on public.friendships
  for select to authenticated using (auth.uid() in (user_a, user_b));

drop policy if exists "see own trades" on public.trades;
create policy "see own trades" on public.trades
  for select to authenticated using (auth.uid() in (from_user, to_user));

-- ───────────────────────── Sync (phone → server) ─────────────────────────

create or replace function public.replace_my_collection(items jsonb) returns void
language plpgsql set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  delete from collection_items where user_id = auth.uid();
  insert into collection_items (user_id, item_key, card, name_key, foil, qty, binder, condition, added)
  select auth.uid(), x.item_key, x.card, x.name_key, coalesce(x.foil, false), x.qty,
         coalesce(x.binder, 'collection'), coalesce(x.condition, 'NM'), coalesce(x.added, now())
  from jsonb_to_recordset(items) as x(
    item_key text, card jsonb, name_key text, foil boolean, qty int,
    binder text, condition text, added timestamptz)
  where x.qty > 0;
end $$;

create or replace function public.replace_my_decks(items jsonb) returns void
language plpgsql set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  delete from decks where user_id = auth.uid();
  insert into decks (user_id, id, data)
  select auth.uid(), d ->> 'id', d from jsonb_array_elements(items) as d;
end $$;

create or replace function public.save_private_state(wishlist jsonb, applied_trades jsonb) returns void
language plpgsql set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into private_state (user_id, wishlist, applied_trades, updated_at)
  values (auth.uid(), wishlist, applied_trades, now())
  on conflict (user_id) do update
    set wishlist = excluded.wishlist, applied_trades = excluded.applied_trades, updated_at = now();
end $$;

create or replace function public.publish_lists(spares jsonb, wants jsonb) returns void
language plpgsql set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into public_lists (user_id, spares, wants, updated_at)
  values (auth.uid(), spares, wants, now())
  on conflict (user_id) do update
    set spares = excluded.spares, wants = excluded.wants, updated_at = now();
end $$;

-- ───────────────────────── Accounts ─────────────────────────

create or replace function public.username_available(name text) returns boolean
language sql stable security definer set search_path = public as $$
  select lower(trim(name)) ~ '^[a-z0-9_]{3,20}$'
     and not exists (select 1 from profiles where username = lower(trim(name)));
$$;
grant execute on function public.username_available(text) to anon, authenticated;

create or replace function public.regenerate_share_token() returns uuid
language plpgsql security definer set search_path = public as $$
declare t uuid := gen_random_uuid();
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  update profiles set share_token = t where id = auth.uid();
  return t;
end $$;

-- Public, read-only Showcase for the share link. Anyone with the token can view.
create or replace function public.get_public_showcase(token uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'username', p.username,
    'display_name', p.display_name,
    'cards', coalesce((
      select jsonb_agg(jsonb_build_object('card', c.card, 'qty', c.qty, 'foil', c.foil) order by c.added desc)
      from collection_items c where c.user_id = p.id and c.binder = 'showcase'
    ), '[]'::jsonb))
  from profiles p where p.share_token = token;
$$;
grant execute on function public.get_public_showcase(uuid) to anon, authenticated;

-- ───────────────────────── Friends ─────────────────────────

create or replace function public.request_friend(target_username text) returns text
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  other uuid;
  existing public.friendships%rowtype;
begin
  if me is null then raise exception 'not signed in'; end if;
  select id into other from profiles where username = lower(trim(target_username));
  if other is null then return 'not_found'; end if;
  if other = me then return 'self'; end if;
  select * into existing from friendships where user_a = least(me, other) and user_b = greatest(me, other);
  if found then
    if existing.status = 'accepted' then return 'already_friends'; end if;
    if existing.requested_by = other then
      update friendships set status = 'accepted'
        where user_a = existing.user_a and user_b = existing.user_b;
      return 'accepted';
    end if;
    return 'already_requested';
  end if;
  insert into friendships (user_a, user_b, status, requested_by)
    values (least(me, other), greatest(me, other), 'pending', me);
  return 'requested';
end $$;

create or replace function public.respond_friend(other uuid, accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if accept then
    update friendships set status = 'accepted'
      where user_a = least(me, other) and user_b = greatest(me, other)
        and status = 'pending' and requested_by = other;
  else
    delete from friendships where user_a = least(me, other) and user_b = greatest(me, other);
  end if;
end $$;

create or replace function public.remove_friend(other uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  delete from friendships where user_a = least(auth.uid(), other) and user_b = greatest(auth.uid(), other);
end $$;

create or replace function public.list_friends()
returns table (id uuid, username text, display_name text, status text, incoming boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.username, p.display_name, f.status, (f.requested_by <> auth.uid())
  from friendships f
  join profiles p on p.id = case when f.user_a = auth.uid() then f.user_b else f.user_a end
  where auth.uid() in (f.user_a, f.user_b)
  order by p.username;
$$;

-- ───────────────────────── Trades ─────────────────────────

create or replace function public.propose_trade(
  to_user uuid, give jsonb, receive jsonb, message text default null, parent uuid default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  new_id uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not are_friends(me, to_user) then raise exception 'you can only trade with friends'; end if;
  if jsonb_array_length(give) = 0 and jsonb_array_length(receive) = 0 then
    raise exception 'a trade needs at least one card';
  end if;
  insert into trades (from_user, to_user, give, receive, message, parent_id)
    values (me, to_user, give, receive, message, parent)
    returning id into new_id;
  if parent is not null then
    update trades set status = 'countered', updated_at = now()
      where id = parent and trades.to_user = me and trades.status = 'proposed';
  end if;
  return new_id;
end $$;

-- action: accept | decline | cancel | complete
create or replace function public.respond_trade(trade_id uuid, action text) returns text
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  t public.trades%rowtype;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into t from trades where id = trade_id for update;
  if not found or me not in (t.from_user, t.to_user) then raise exception 'trade not found'; end if;

  if action = 'accept' and t.status = 'proposed' and me = t.to_user then
    update trades set status = 'accepted', updated_at = now() where id = trade_id;
  elsif action = 'decline' and t.status = 'proposed' and me = t.to_user then
    update trades set status = 'declined', updated_at = now() where id = trade_id;
  elsif action = 'cancel' and (t.status = 'accepted' or (t.status = 'proposed' and me = t.from_user)) then
    update trades set status = 'cancelled', updated_at = now() where id = trade_id;
  elsif action = 'complete' and t.status = 'accepted' then
    if me = t.from_user then t.from_done := true; else t.to_done := true; end if;
    update trades set
      from_done = t.from_done,
      to_done = t.to_done,
      status = case when t.from_done and t.to_done then 'completed' else 'accepted' end,
      updated_at = now()
      where id = trade_id;
  else
    raise exception 'cannot % a % trade', action, t.status;
  end if;
  select status into t.status from trades where id = trade_id;
  return t.status;
end $$;
