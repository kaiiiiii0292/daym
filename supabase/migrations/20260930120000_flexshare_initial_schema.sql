create table public.users (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users (id) on delete set null,
  full_name text not null check (length(trim(full_name)) > 0),
  student_id_number text not null unique check (length(trim(student_id_number)) > 0),
  department text not null check (
    department in ('IT', 'Engineering', 'Architecture', 'Nursing', 'Business')
  ),
  role text not null default 'borrower' check (
    role in ('borrower', 'lender', 'flexrunner')
  ),
  is_id_verified boolean not null default false,
  wallet_balance numeric(12, 2) not null default 0 check (wallet_balance >= 0),
  created_at timestamptz not null default now()
);

comment on column public.users.auth_user_id is
  'Nullable Supabase Auth link; fictional seed profiles are intentionally unlinked.';
comment on column public.users.is_id_verified is
  'Verification is managed by trusted backend code; clients cannot update this field.';

create table public.equipment_items (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users (id) on delete restrict,
  title text not null check (length(trim(title)) > 0),
  category text not null check (length(trim(category)) > 0),
  hourly_rate_php numeric(10, 2) not null check (hourly_rate_php >= 0),
  daily_rate_php numeric(10, 2) not null check (daily_rate_php >= 0),
  protection_fee_php numeric(10, 2) not null default 0 check (protection_fee_php >= 0),
  campus_building text not null check (
    campus_building in (
      'IT Building',
      'Engineering Building',
      'Architecture Studio',
      'Nursing Building',
      'CBA Building'
    )
  ),
  lat double precision not null check (lat between -90 and 90),
  lng double precision not null check (lng between -180 and 180),
  is_available boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.rentals (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.equipment_items (id) on delete restrict,
  borrower_id uuid not null references public.users (id) on delete restrict,
  duration_type text not null check (duration_type in ('hourly', 'daily')),
  base_amount numeric(10, 2) not null check (base_amount >= 0),
  platform_commission numeric(4, 3) not null check (
    platform_commission between 0.100 and 0.150
  ),
  protection_fee numeric(10, 2) not null default 0 check (protection_fee >= 0),
  late_fee numeric(10, 2) not null default 0 check (late_fee >= 0),
  payment_method text not null check (payment_method in ('GCash', 'Maya')),
  status text not null default 'requested' check (
    status in ('requested', 'confirmed', 'active', 'completed', 'cancelled', 'rejected')
  ),
  due_timestamp timestamptz not null,
  created_at timestamptz not null default now(),
  check (due_timestamp > created_at)
);

comment on column public.rentals.base_amount is 'Rental base amount in PHP.';
comment on column public.rentals.platform_commission is
  'Commission rate as a fraction: 0.100 means 10%, through 0.150 for 15%.';
comment on column public.rentals.protection_fee is 'Protection fee in PHP.';
comment on column public.rentals.late_fee is 'Late fee in PHP.';
comment on table public.rentals is
  'Client writes are disabled; trusted backend code validates quotes and rental status transitions.';

create table public.qr_handoffs (
  id uuid primary key default gen_random_uuid(),
  rental_id uuid not null unique references public.rentals (id) on delete restrict,
  qr_token text not null unique,
  before_photo_url text,
  after_photo_url text,
  pickup_verified_at timestamptz,
  return_verified_at timestamptz,
  check (
    return_verified_at is null
    or (
      pickup_verified_at is not null
      and return_verified_at >= pickup_verified_at
    )
  )
);

comment on column public.qr_handoffs.qr_token is
  'Secret handoff token; omitted from authenticated column-level SELECT grants.';
comment on table public.qr_handoffs is
  'Client reads are participant-scoped; inserts and verification writes are server-mediated.';

create table public.flexrunner_deliveries (
  id uuid primary key default gen_random_uuid(),
  rental_id uuid not null unique references public.rentals (id) on delete restrict,
  runner_id uuid references public.users (id) on delete restrict,
  pickup_building text not null check (
    pickup_building in (
      'IT Building',
      'Engineering Building',
      'Architecture Studio',
      'Nursing Building',
      'CBA Building'
    )
  ),
  dropoff_classroom text not null check (length(trim(dropoff_classroom)) > 0),
  delivery_fee numeric(10, 2) not null check (delivery_fee >= 0),
  platform_cut numeric(10, 2) not null default 0 check (
    platform_cut >= 0 and platform_cut <= delivery_fee
  ),
  status text not null default 'open' check (
    status in ('open', 'assigned', 'picked_up', 'delivered')
  ),
  created_at timestamptz not null default now(),
  check (
    (status = 'open' and runner_id is null)
    or (status <> 'open' and runner_id is not null)
  )
);

comment on column public.flexrunner_deliveries.delivery_fee is 'Delivery fee in PHP.';
comment on column public.flexrunner_deliveries.platform_cut is 'Platform share of the delivery fee in PHP.';
comment on table public.flexrunner_deliveries is
  'Client reads are runner/booking scoped; assignment and status writes are server-mediated.';

create index equipment_items_owner_idx on public.equipment_items (owner_id);
create index equipment_items_available_building_idx
  on public.equipment_items (campus_building)
  where is_available;
create index rentals_borrower_idx on public.rentals (borrower_id);
create index rentals_item_idx on public.rentals (item_id);
create index deliveries_open_idx on public.flexrunner_deliveries (created_at)
  where status = 'open';

alter table public.users enable row level security;
alter table public.equipment_items enable row level security;
alter table public.rentals enable row level security;
alter table public.qr_handoffs enable row level security;
alter table public.flexrunner_deliveries enable row level security;

revoke all on public.users, public.equipment_items, public.rentals,
  public.qr_handoffs, public.flexrunner_deliveries from anon, authenticated;

grant select on public.users, public.equipment_items, public.rentals,
  public.flexrunner_deliveries to authenticated;
grant select (id, rental_id, before_photo_url, after_photo_url,
  pickup_verified_at, return_verified_at) on public.qr_handoffs to authenticated;
grant insert on public.users to authenticated;
grant insert, update, delete on public.equipment_items to authenticated;

create policy users_read_self
  on public.users for select to authenticated
  using (auth_user_id = (select auth.uid()));

create policy users_create_borrower_profile
  on public.users for insert to authenticated
  with check (
    auth_user_id = (select auth.uid())
    and role = 'borrower'
    and not is_id_verified
    and wallet_balance = 0
  );

create policy equipment_read_available_or_owned
  on public.equipment_items for select to authenticated
  using (
    is_available
    or exists (
      select 1
      from public.users as owner
      where owner.id = equipment_items.owner_id
        and owner.auth_user_id = (select auth.uid())
    )
  );

create policy equipment_create_verified_lender_items
  on public.equipment_items for insert to authenticated
  with check (
    exists (
      select 1
      from public.users as owner
      where owner.id = equipment_items.owner_id
        and owner.auth_user_id = (select auth.uid())
        and owner.role = 'lender'
        and owner.is_id_verified
    )
  );

create policy equipment_update_owned_items
  on public.equipment_items for update to authenticated
  using (
    exists (
      select 1
      from public.users as owner
      where owner.id = equipment_items.owner_id
        and owner.auth_user_id = (select auth.uid())
        and owner.role = 'lender'
        and owner.is_id_verified
    )
  )
  with check (
    exists (
      select 1
      from public.users as owner
      where owner.id = equipment_items.owner_id
        and owner.auth_user_id = (select auth.uid())
        and owner.role = 'lender'
        and owner.is_id_verified
    )
  );

create policy equipment_delete_owned_items
  on public.equipment_items for delete to authenticated
  using (
    exists (
      select 1
      from public.users as owner
      where owner.id = equipment_items.owner_id
        and owner.auth_user_id = (select auth.uid())
        and owner.role = 'lender'
        and owner.is_id_verified
    )
  );

create policy rentals_read_participant
  on public.rentals for select to authenticated
  using (
    exists (
      select 1
      from public.users as borrower
      where borrower.id = rentals.borrower_id
        and borrower.auth_user_id = (select auth.uid())
    )
    or exists (
      select 1
      from public.equipment_items as item
      join public.users as owner on owner.id = item.owner_id
      where item.id = rentals.item_id
        and owner.auth_user_id = (select auth.uid())
    )
  );

create policy qr_handoffs_read_rental_participants
  on public.qr_handoffs for select to authenticated
  using (
    exists (
      select 1
      from public.rentals as rental
      where rental.id = qr_handoffs.rental_id
    )
  );

create policy deliveries_read_open_or_involved
  on public.flexrunner_deliveries for select to authenticated
  using (
    (
      status = 'open'
      and exists (
        select 1
        from public.users as runner
        where runner.auth_user_id = (select auth.uid())
          and runner.role = 'flexrunner'
          and runner.is_id_verified
      )
    )
    or exists (
      select 1
      from public.users as runner
      where runner.id = flexrunner_deliveries.runner_id
        and runner.auth_user_id = (select auth.uid())
    )
    or exists (
      select 1
      from public.rentals as rental
      where rental.id = flexrunner_deliveries.rental_id
    )
  );

-- Demo identities are fictional, unlinked to Auth, and deliberately unverified.
insert into public.users (
  id, full_name, student_id_number, department, role, is_id_verified, wallet_balance
) values
  ('00000000-0000-4000-8000-000000000001', 'Mika Reyes', 'DEMO-PSU-IT-001', 'IT', 'lender', false, 0),
  ('00000000-0000-4000-8000-000000000002', 'Noah Santos', 'DEMO-PSU-ENG-001', 'Engineering', 'lender', false, 0),
  ('00000000-0000-4000-8000-000000000003', 'Leah Dizon', 'DEMO-PSU-ARCH-001', 'Architecture', 'lender', false, 0),
  ('00000000-0000-4000-8000-000000000004', 'Gab Cruz', 'DEMO-PSU-NURS-001', 'Nursing', 'lender', false, 0),
  ('00000000-0000-4000-8000-000000000005', 'Ari Lim', 'DEMO-PSU-BUS-001', 'Business', 'lender', false, 0),
  ('00000000-0000-4000-8000-000000000006', 'Kai Mendoza', 'DEMO-PSU-RUN-001', 'IT', 'flexrunner', false, 0),
  ('00000000-0000-4000-8000-000000000007', 'Sam Flores', 'DEMO-PSU-BOR-001', 'Business', 'borrower', false, 0)
on conflict (id) do nothing;

-- Coordinates are illustrative campus pins; confirm exact locations before production use.
insert into public.equipment_items (
  id, owner_id, title, category, hourly_rate_php, daily_rate_php,
  protection_fee_php, campus_building, lat, lng, is_available
) values
  (
    '10000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000001',
    'Casio fx-991EX Calculator', 'Calculator', 8, 80, 20,
    'IT Building', 9.77660, 118.73320, true
  ),
  (
    '10000000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8000-000000000005',
    'Canon EOS DSLR Camera', 'Camera', 150, 800, 200,
    'CBA Building', 9.77730, 118.73510, true
  ),
  (
    '10000000-0000-4000-8000-000000000003',
    '00000000-0000-4000-8000-000000000003',
    'Wacom Drawing Tablet', 'Drawing Tablet', 30, 180, 50,
    'Architecture Studio', 9.77710, 118.73450, true
  ),
  (
    '10000000-0000-4000-8000-000000000004',
    '00000000-0000-4000-8000-000000000002',
    'Arduino Uno Kit', 'Electronics', 20, 120, 40,
    'Engineering Building', 9.77610, 118.73410, true
  ),
  (
    '10000000-0000-4000-8000-000000000005',
    '00000000-0000-4000-8000-000000000004',
    'Nursing Lab Gear', 'Lab Gear', 25, 160, 50,
    'Nursing Building', 9.77790, 118.73320, true
  )
on conflict (id) do nothing;