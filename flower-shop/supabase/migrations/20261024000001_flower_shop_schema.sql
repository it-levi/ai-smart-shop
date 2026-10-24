-- Applied to Supabase project "Flower Shop" (dbpoikfpkevtmhoniabl)

-- Profiles: one row per signed-up user (customers and the shop owner)
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  role text not null default 'customer' check (role in ('customer','admin')),
  created_at timestamptz not null default now()
);

-- Products shown on the site
create table public.products (
  id bigint generated always as identity primary key,
  name text not null,
  description text,
  category text,
  price numeric(10,2) not null check (price >= 0),
  image_url text,
  is_active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

-- Orders (guests or signed-in customers)
create table public.orders (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete set null,
  customer_name text not null,
  customer_phone text not null,
  recipient_name text,
  recipient_phone text,
  delivery_address text,
  delivery_date date,
  delivery_time text,
  card_message text,
  notes text,
  status text not null default 'new'
    check (status in ('new','confirmed','preparing','out_for_delivery','delivered','cancelled')),
  total numeric(10,2) not null default 0,
  created_at timestamptz not null default now()
);
create index orders_user_id_idx on public.orders(user_id);
create index orders_status_idx on public.orders(status, created_at desc);

create table public.order_items (
  id bigint generated always as identity primary key,
  order_id bigint not null references public.orders(id) on delete cascade,
  product_id bigint references public.products(id) on delete set null,
  product_name text not null,
  unit_price numeric(10,2) not null,
  quantity int not null check (quantity between 1 and 50)
);
create index order_items_order_id_idx on public.order_items(order_id);
create index order_items_product_id_idx on public.order_items(product_id);

-- Helper: is the current user the shop owner? (moved to schema "private" below)
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- Create a profile automatically on sign-up
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'phone');
  return new;
end;
$$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Place an order: prices come from the products table, never from the browser
create or replace function public.place_order(
  p_items jsonb,
  p_customer_name text,
  p_customer_phone text,
  p_recipient_name text default null,
  p_recipient_phone text default null,
  p_delivery_address text default null,
  p_delivery_date date default null,
  p_delivery_time text default null,
  p_card_message text default null,
  p_notes text default null
)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_order_id bigint;
  v_item jsonb;
  v_product public.products%rowtype;
  v_qty int;
  v_total numeric(10,2) := 0;
begin
  if coalesce(trim(p_customer_name), '') = '' or coalesce(trim(p_customer_phone), '') = '' then
    raise exception 'Name and phone are required';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 20 then
    raise exception 'Order must have 1 to 20 items';
  end if;

  insert into public.orders (user_id, customer_name, customer_phone, recipient_name, recipient_phone,
    delivery_address, delivery_date, delivery_time, card_message, notes)
  values (auth.uid(), left(p_customer_name, 120), left(p_customer_phone, 30), left(p_recipient_name, 120),
    left(p_recipient_phone, 30), left(p_delivery_address, 500), p_delivery_date, left(p_delivery_time, 50),
    left(p_card_message, 500), left(p_notes, 1000))
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select * into v_product from public.products
      where id = (v_item->>'product_id')::bigint and is_active;
    if not found then
      raise exception 'Product not available';
    end if;
    v_qty := coalesce((v_item->>'quantity')::int, 1);
    if v_qty < 1 or v_qty > 50 then
      raise exception 'Invalid quantity';
    end if;
    insert into public.order_items (order_id, product_id, product_name, unit_price, quantity)
    values (v_order_id, v_product.id, v_product.name, v_product.price, v_qty);
    v_total := v_total + v_product.price * v_qty;
  end loop;

  update public.orders set total = v_total where id = v_order_id;
  return v_order_id;
end;
$$;

revoke all on function public.place_order(jsonb,text,text,text,text,text,date,text,text,text) from public;
grant execute on function public.place_order(jsonb,text,text,text,text,text,date,text,text,text) to anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;

-- Row level security
alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

-- profiles: see/edit your own, the owner sees all. Role can't be changed from the browser.
create policy "profiles_select" on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));
create policy "profiles_update_own" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
revoke update on public.profiles from anon, authenticated;
grant update (full_name, phone) on public.profiles to authenticated;

-- products: everyone sees active ones, the owner manages everything
create policy "products_select" on public.products for select to anon, authenticated
  using (is_active or (select public.is_admin()));
create policy "products_admin_insert" on public.products for insert to authenticated
  with check ((select public.is_admin()));
create policy "products_admin_update" on public.products for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "products_admin_delete" on public.products for delete to authenticated
  using ((select public.is_admin()));

-- orders: customers see their own, the owner sees and updates all. Inserts only via place_order.
create policy "orders_select" on public.orders for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy "orders_admin_update" on public.orders for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "orders_admin_delete" on public.orders for delete to authenticated
  using ((select public.is_admin()));

create policy "order_items_select" on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id
                 and (o.user_id = (select auth.uid()) or (select public.is_admin()))));
