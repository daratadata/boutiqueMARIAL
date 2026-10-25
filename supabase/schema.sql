-- Boutique du Sanctuaire marial d'Abidjan : base de données Supabase
-- À coller dans Supabase > SQL Editor > Run. Peut être relancé sans danger.

-- 1. Administrateurs (comptes autorisés à gérer la boutique)
create table if not exists admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from admins where user_id = auth.uid()) $$;

-- 2. Catalogue
create table if not exists categories (
  id text primary key,
  label text not null,
  icon text not null default 'chap',
  position int not null default 0
);
create table if not exists products (
  id bigint generated always as identity primary key,
  category_id text references categories(id) on update cascade,
  name text not null,
  description text not null default '',
  price int not null check (price > 0),          -- en FCFA
  old_price int not null default 0,              -- prix barré si promotion
  stock int not null default 0 check (stock >= 0),
  image_url text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists services (
  id bigint generated always as identity primary key,
  title text not null,
  description text not null default '',
  icon text not null default 'truck',
  position int not null default 0,
  active boolean not null default true
);

-- 3. Livraison : zones, distances saisies à la main, réglages
create table if not exists delivery_zones (
  name text primary key
);
create table if not exists delivery_distances (
  zone_a text not null references delivery_zones(name) on update cascade,
  zone_b text not null references delivery_zones(name) on update cascade,
  km numeric(5,1) not null check (km >= 0),
  fixed_price int not null default 0,            -- 0 = calcul automatique
  primary key (zone_a, zone_b),
  check (zone_a < zone_b)
);
create table if not exists settings (
  key text primary key,
  value text not null
);

-- 4. Commandes de la boutique
create table if not exists orders (
  id bigint generated always as identity primary key,
  ref text unique not null,                      -- ex. CMD-4821
  customer_name text not null,
  customer_phone text not null,
  delivery_mode text not null default 'retrait' check (delivery_mode in ('retrait','livraison')),
  delivery_zone text references delivery_zones(name),
  delivery_fee int not null default 0,
  total int not null,
  status text not null default 'En attente de paiement',
  wave_transaction text,
  created_at timestamptz not null default now()
);
create table if not exists order_items (
  id bigint generated always as identity primary key,
  order_id bigint not null references orders(id) on delete cascade,
  product_id bigint references products(id) on delete set null,
  product_name text not null,
  unit_price int not null,
  quantity int not null check (quantity > 0)
);

-- 5. Courses de livraison pour des tiers
create table if not exists delivery_requests (
  id bigint generated always as identity primary key,
  ref text unique not null,                      -- ex. LIV-1573
  requester_name text not null,
  requester_phone text not null,
  from_zone text not null references delivery_zones(name),
  to_zone text not null references delivery_zones(name),
  km numeric(5,1) not null,
  urgent boolean not null default false,
  parcel text not null,
  price int not null,
  status text not null default 'Demandée',
  courier_name text,
  wave_transaction text,
  created_at timestamptz not null default now()
);

-- 6. Sécurité (RLS) : le public lit le catalogue et passe commande ;
--    seuls les administrateurs gèrent le reste.
alter table admins             enable row level security;
alter table categories         enable row level security;
alter table products           enable row level security;
alter table services           enable row level security;
alter table delivery_zones     enable row level security;
alter table delivery_distances enable row level security;
alter table settings           enable row level security;
alter table orders             enable row level security;
alter table order_items        enable row level security;
alter table delivery_requests  enable row level security;

do $$
declare t text;
begin
  foreach t in array array['categories','products','services','delivery_zones','delivery_distances','settings','orders','order_items','delivery_requests']
  loop
    execute format('drop policy if exists admin_all on %I', t);
    execute format('create policy admin_all on %I for all using (is_admin()) with check (is_admin())', t);
  end loop;
end $$;

drop policy if exists public_read on categories;
create policy public_read on categories for select using (true);
drop policy if exists public_read on products;
create policy public_read on products for select using (active);
drop policy if exists public_read on services;
create policy public_read on services for select using (active);
drop policy if exists public_read on delivery_zones;
create policy public_read on delivery_zones for select using (true);
drop policy if exists public_read on delivery_distances;
create policy public_read on delivery_distances for select using (true);
drop policy if exists public_read on settings;
create policy public_read on settings for select using (key <> 'admin_pin');

-- Les commandes passent par la fonction create_order (section 6 bis) : pas d'insertion directe
drop policy if exists public_insert on orders;
drop policy if exists public_insert on order_items;
-- Les courses de livraison peuvent être demandées par le public, mais pas lues
drop policy if exists public_insert on delivery_requests;
create policy public_insert on delivery_requests for insert with check (status = 'Demandée');

-- 6 bis. Création d'une commande : le prix est recalculé côté serveur (impossible de le falsifier)
create or replace function create_order(
  p_ref text, p_name text, p_phone text, p_mode text, p_zone text, p_items jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_fee int := 0; v_sub int := 0; v_id bigint;
  v_km numeric; v_fixed int; v_base int; v_perkm int;
  it jsonb; pr products%rowtype; q int;
begin
  if coalesce(trim(p_name),'') = '' or coalesce(trim(p_phone),'') = '' then
    raise exception 'Nom et téléphone requis';
  end if;
  if p_mode not in ('retrait','livraison') then raise exception 'Mode de réception invalide'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Panier vide'; end if;
  if p_mode = 'livraison' then
    select km, fixed_price into v_km, v_fixed from delivery_distances
      where (zone_a = 'Sanctuaire' and zone_b = p_zone) or (zone_b = 'Sanctuaire' and zone_a = p_zone);
    if v_km is null then raise exception 'Zone de livraison inconnue'; end if;
    select value::int into v_base from settings where key = 'delivery_base_fee';
    select value::int into v_perkm from settings where key = 'delivery_price_per_km';
    v_fee := (round((case when coalesce(v_fixed,0) > 0 then v_fixed else v_base + v_km * v_perkm end) / 100.0) * 100)::int;
  end if;
  insert into orders (ref, customer_name, customer_phone, delivery_mode, delivery_zone, delivery_fee, total)
  values (p_ref, trim(p_name), trim(p_phone), p_mode, case when p_mode = 'livraison' then p_zone end, v_fee, 0)
  returning id into v_id;
  for it in select * from jsonb_array_elements(p_items) loop
    q := (it->>'quantity')::int;
    select * into pr from products where id = (it->>'product_id')::bigint and active for update;
    if not found or q < 1 or pr.stock < q then
      raise exception 'Article indisponible ou stock insuffisant';
    end if;
    insert into order_items (order_id, product_id, product_name, unit_price, quantity)
    values (v_id, pr.id, pr.name, pr.price, q);
    update products set stock = stock - q where id = pr.id;
    v_sub := v_sub + pr.price * q;
  end loop;
  update orders set total = v_sub + v_fee where id = v_id;
  return v_sub + v_fee;
end $$;
revoke all on function create_order(text,text,text,text,text,jsonb) from public;
grant execute on function create_order(text,text,text,text,text,jsonb) to anon, authenticated;

-- 7. Photos des articles (Storage) : lecture publique, écriture réservée aux administrateurs
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do nothing;
drop policy if exists "photos lisibles" on storage.objects;
create policy "photos lisibles" on storage.objects for select using (bucket_id = 'product-images');
drop policy if exists "photos admin" on storage.objects;
create policy "photos admin" on storage.objects for all
  using (bucket_id = 'product-images' and is_admin())
  with check (bucket_id = 'product-images' and is_admin());

-- 8. Données de départ
insert into categories (id, label, icon, position) values
  ('chap','Chapelets','chap',1), ('stat','Statues','stat',2), ('img','Images','img',3),
  ('cand','Bougies','cand',4), ('book','Livres','book',5), ('med','Médailles','med',6)
on conflict (id) do nothing;

insert into products (category_id, name, description, price, old_price, stock)
select * from (values
  ('chap','Chapelet en bois d''olivier','Chapelet artisanal en bois d''olivier.',1500,0,24),
  ('stat','Statue de Notre-Dame','Statue de la Vierge Marie pour la maison ou l''oratoire.',8000,9500,8),
  ('img','Images pieuses (lot de 5)','Cinq images pieuses à offrir ou à glisser dans un missel.',1000,0,40),
  ('cand','Bougie votive','Bougie pour la prière et les intentions.',500,0,100),
  ('med','Médaille miraculeuse','Médaille de la Vierge miraculeuse.',1000,0,60),
  ('book','Livre de prières','Recueil de prières pour chaque jour.',3000,3500,6)
) as v(category_id, name, description, price, old_price, stock)
where not exists (select 1 from products);

insert into services (title, description, icon, position)
select * from (values
  ('Livraison à Abidjan','Tarif calculé selon la distance','truck',1),
  ('Envoi de colis','Le sanctuaire livre pour vous','box',2),
  ('Paiement par Wave','Rapide, sans carte bancaire','wave',3),
  ('Retrait gratuit','Directement au sanctuaire','pin',4)
) as v(title, description, icon, position)
where not exists (select 1 from services);

insert into delivery_zones (name) values
  ('Abobo'),('Cocody'),('Marcory'),('Plateau'),('Sanctuaire'),('Yopougon')
on conflict do nothing;

-- Distances d'exemple en km : à corriger dans le tableau de bord (zone_a < zone_b par ordre alphabétique)
insert into delivery_distances (zone_a, zone_b, km) values
  ('Abobo','Cocody',14), ('Abobo','Marcory',18), ('Abobo','Plateau',12),
  ('Abobo','Sanctuaire',8), ('Abobo','Yopougon',12),
  ('Cocody','Marcory',12), ('Cocody','Plateau',9), ('Cocody','Sanctuaire',7), ('Cocody','Yopougon',18),
  ('Marcory','Plateau',6), ('Marcory','Sanctuaire',6), ('Marcory','Yopougon',14),
  ('Plateau','Sanctuaire',5), ('Plateau','Yopougon',11),
  ('Sanctuaire','Yopougon',10)
on conflict do nothing;

insert into settings (key, value) values
  ('delivery_base_fee','500'),
  ('delivery_price_per_km','150'),
  ('delivery_urgent_fee','500'),
  ('wave_number','07 00 00 00 00')
on conflict (key) do nothing;

-- 9. Après avoir créé votre compte (Authentication > Users), donnez-vous les droits administrateur :
--    insert into admins (user_id) select id from auth.users where email = 'votre@email.com';
