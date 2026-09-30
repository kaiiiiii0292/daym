alter table public.qr_handoffs
  add column token_issued_by uuid references public.users (id) on delete restrict,
  add column pickup_verified_by uuid references public.users (id) on delete restrict,
  add column return_verified_by uuid references public.users (id) on delete restrict;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'flexshare-handoff-photos',
  'flexshare-handoff-photos',
  false,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

create or replace function public.is_handoff_participant(p_rental_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.rentals as rental
    join public.equipment_items as item on item.id = rental.item_id
    join public.users as borrower on borrower.id = rental.borrower_id
    join public.users as owner on owner.id = item.owner_id
    left join public.flexrunner_deliveries as delivery
      on delivery.rental_id = rental.id
    left join public.users as runner on runner.id = delivery.runner_id
    where rental.id::text = p_rental_id
      and (
        (borrower.auth_user_id = auth.uid() and borrower.is_id_verified)
        or (owner.auth_user_id = auth.uid() and owner.is_id_verified)
        or (runner.auth_user_id = auth.uid() and runner.is_id_verified)
      )
  )
$$;

revoke all on function public.is_handoff_participant(text) from public, anon;
grant execute on function public.is_handoff_participant(text) to authenticated;

create policy flexshare_participants_upload_handoff_photos
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'flexshare-handoff-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (storage.foldername(name))[2] is not null
    and (
      left(storage.filename(name), 7) = 'pickup_'
      or left(storage.filename(name), 7) = 'return_'
    )
    and public.is_handoff_participant((storage.foldername(name))[2])
  );

create policy flexshare_participants_read_handoff_photos
  on storage.objects for select to authenticated
  using (
    bucket_id = 'flexshare-handoff-photos'
    and (storage.foldername(name))[2] is not null
    and public.is_handoff_participant((storage.foldername(name))[2])
  );

create or replace function public.list_my_rental_handoffs()
returns table (
  rental_id uuid,
  item_title text,
  borrower_id uuid,
  owner_id uuid,
  due_timestamp timestamptz,
  duration_type text,
  duration_count integer,
  rental_status text,
  payment_status text,
  pickup_verified_at timestamptz,
  return_verified_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    rental.id,
    item.title,
    rental.borrower_id,
    item.owner_id,
    rental.due_timestamp,
    rental.duration_type,
    rental.duration_count,
    rental.status,
    rental.payment_status,
    handoff.pickup_verified_at,
    handoff.return_verified_at
  from public.rentals as rental
  join public.equipment_items as item on item.id = rental.item_id
  join public.users as borrower on borrower.id = rental.borrower_id
  join public.users as owner on owner.id = item.owner_id
  left join public.flexrunner_deliveries as delivery
    on delivery.rental_id = rental.id
  left join public.users as runner on runner.id = delivery.runner_id
  left join public.qr_handoffs as handoff on handoff.rental_id = rental.id
  where auth.uid() is not null
    and (
      borrower.auth_user_id = auth.uid()
      or owner.auth_user_id = auth.uid()
      or runner.auth_user_id = auth.uid()
    )
  order by rental.created_at desc
$$;

create or replace function public.get_rental_handoff_qr(p_rental_id uuid)
returns table (out_token text, out_phase text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor public.users%rowtype;
  v_rental public.rentals%rowtype;
  v_owner_id uuid;
  v_runner_id uuid;
  v_handoff public.qr_handoffs%rowtype;
begin
  select profile.* into v_actor
  from public.users as profile
  where profile.auth_user_id = auth.uid();

  if not found or not v_actor.is_id_verified then
    raise exception using message = 'A verified PSU profile is required for handoff.';
  end if;

  select rental.* into v_rental
  from public.rentals as rental
  where rental.id = p_rental_id
  for update;

  if not found then
    raise exception using message = 'Rental not found.';
  end if;

  select item.owner_id into v_owner_id
  from public.equipment_items as item
  where item.id = v_rental.item_id;

  select delivery.runner_id into v_runner_id
  from public.flexrunner_deliveries as delivery
  where delivery.rental_id = p_rental_id;

  if v_actor.id <> v_rental.borrower_id
    and v_actor.id <> v_owner_id
    and (v_runner_id is null or v_actor.id <> v_runner_id) then
    raise exception using message = 'You are not a participant in this handoff.';
  end if;

  if v_rental.status not in ('confirmed', 'active')
    or v_rental.payment_status <> 'paid' then
    raise exception using message = 'Handoff is available after payment is confirmed.';
  end if;

  insert into public.qr_handoffs (rental_id, qr_token, token_issued_by)
  values (p_rental_id, gen_random_uuid()::text, v_actor.id)
  on conflict (rental_id) do nothing;

  select handoff.* into v_handoff
  from public.qr_handoffs as handoff
  where handoff.rental_id = p_rental_id
  for update;

  if v_handoff.token_issued_by is null then
    update public.qr_handoffs
      set token_issued_by = v_actor.id
      where rental_id = p_rental_id;
    v_handoff.token_issued_by := v_actor.id;
  end if;

  if v_handoff.token_issued_by <> v_actor.id then
    raise exception using message = 'Ask the other handoff participant to display their QR code.';
  end if;

  if v_handoff.return_verified_at is not null then
    raise exception using message = 'This rental handoff is already complete.';
  end if;

  if v_handoff.pickup_verified_at is null and v_rental.status <> 'confirmed' then
    raise exception using message = 'Pickup handoff is no longer available.';
  end if;

  return query select
    v_handoff.qr_token,
    case when v_handoff.pickup_verified_at is null then 'pickup' else 'return' end;
end;
$$;

create or replace function public.verify_rental_handoff(
  p_rental_id uuid,
  p_qr_token text,
  p_phase text,
  p_photo_path text
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor public.users%rowtype;
  v_rental public.rentals%rowtype;
  v_owner_id uuid;
  v_runner_id uuid;
  v_handoff public.qr_handoffs%rowtype;
  v_now timestamptz := now();
  v_photo_prefix text;
begin
  if p_phase is null
    or p_phase not in ('pickup', 'return')
    or p_qr_token is null then
    raise exception using message = 'Invalid handoff QR code or phase.';
  end if;

  select profile.* into v_actor
  from public.users as profile
  where profile.auth_user_id = auth.uid();

  if not found or not v_actor.is_id_verified then
    raise exception using message = 'A verified PSU profile is required for handoff.';
  end if;

  select rental.* into v_rental
  from public.rentals as rental
  where rental.id = p_rental_id
  for update;

  if not found then
    raise exception using message = 'Rental not found.';
  end if;

  select item.owner_id into v_owner_id
  from public.equipment_items as item
  where item.id = v_rental.item_id;

  select delivery.runner_id into v_runner_id
  from public.flexrunner_deliveries as delivery
  where delivery.rental_id = p_rental_id;

  if v_actor.id <> v_rental.borrower_id
    and v_actor.id <> v_owner_id
    and (v_runner_id is null or v_actor.id <> v_runner_id) then
    raise exception using message = 'You are not a participant in this handoff.';
  end if;

  select handoff.* into v_handoff
  from public.qr_handoffs as handoff
  where handoff.rental_id = p_rental_id
  for update;

  if not found or v_handoff.qr_token <> p_qr_token then
    raise exception using message = 'This QR code is invalid or has expired.';
  end if;

  if v_handoff.token_issued_by = v_actor.id then
    raise exception using message = 'The other handoff participant must scan this QR code.';
  end if;

  v_photo_prefix := auth.uid()::text || '/' || p_rental_id::text || '/' || p_phase || '_';
  if p_photo_path is null or left(p_photo_path, length(v_photo_prefix)) <> v_photo_prefix
    or not exists (
      select 1 from storage.objects as photo
      where photo.bucket_id = 'flexshare-handoff-photos'
        and photo.name = p_photo_path
    ) then
    raise exception using message = 'Capture and upload the required condition photo.';
  end if;

  if p_phase = 'pickup' then
    if v_rental.status <> 'confirmed'
      or v_rental.payment_status <> 'paid'
      or v_handoff.pickup_verified_at is not null then
      raise exception using message = 'Pickup handoff is not available.';
    end if;

    update public.qr_handoffs
      set before_photo_url = p_photo_path,
          pickup_verified_at = v_now,
          pickup_verified_by = v_actor.id,
          token_issued_by = v_actor.id,
          qr_token = gen_random_uuid()::text
      where rental_id = p_rental_id;
    update public.rentals
      set status = 'active',
          due_timestamp = v_now + case v_rental.duration_type
            when 'hourly' then v_rental.duration_count * interval '1 hour'
            else v_rental.duration_count * interval '1 day'
          end
      where id = p_rental_id;
  else
    if v_rental.status <> 'active'
      or v_handoff.pickup_verified_at is null
      or v_handoff.return_verified_at is not null then
      raise exception using message = 'Return handoff is not available.';
    end if;

    update public.qr_handoffs
      set after_photo_url = p_photo_path,
          return_verified_at = v_now,
          return_verified_by = v_actor.id
      where rental_id = p_rental_id;
    update public.rentals set status = 'completed' where id = p_rental_id;
    update public.equipment_items
      set is_available = true
      where id = v_rental.item_id;
  end if;

  return v_now;
end;
$$;

create or replace function public.list_my_flexrunner_deliveries()
returns table (
  delivery_id uuid,
  rental_id uuid,
  item_title text,
  pickup_building text,
  dropoff_classroom text,
  delivery_fee numeric,
  platform_cut numeric,
  delivery_status text,
  created_at timestamptz,
  pickup_verified_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_runner public.users%rowtype;
begin
  select profile.* into v_runner
  from public.users as profile
  where profile.auth_user_id = auth.uid();

  if not found or v_runner.role <> 'flexrunner' or not v_runner.is_id_verified then
    raise exception using message = 'A verified FlexRunner profile is required.';
  end if;

  return query
    select
      delivery.id,
      delivery.rental_id,
      item.title,
      delivery.pickup_building,
      delivery.dropoff_classroom,
      delivery.delivery_fee,
      delivery.platform_cut,
      delivery.status,
      delivery.created_at,
      handoff.pickup_verified_at
    from public.flexrunner_deliveries as delivery
    join public.rentals as rental on rental.id = delivery.rental_id
    join public.equipment_items as item on item.id = rental.item_id
    left join public.qr_handoffs as handoff on handoff.rental_id = rental.id
    where (
      delivery.status = 'open'
      and rental.payment_status = 'paid'
      and rental.status = 'confirmed'
    ) or delivery.runner_id = v_runner.id
    order by case when delivery.status = 'open' then 0 else 1 end, delivery.created_at;
end;
$$;

create or replace function public.accept_flexrunner_delivery(p_delivery_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_runner public.users%rowtype;
begin
  select profile.* into v_runner
  from public.users as profile
  where profile.auth_user_id = auth.uid();

  if not found or v_runner.role <> 'flexrunner' or not v_runner.is_id_verified then
    raise exception using message = 'A verified FlexRunner profile is required.';
  end if;

  update public.flexrunner_deliveries
    set runner_id = v_runner.id, status = 'assigned'
    where id = p_delivery_id and status = 'open' and runner_id is null;

  if not found then
    raise exception using message = 'This delivery was already accepted.';
  end if;
end;
$$;

create or replace function public.update_flexrunner_delivery_status(
  p_delivery_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_runner public.users%rowtype;
  v_current_status text;
begin
  select profile.* into v_runner
  from public.users as profile
  where profile.auth_user_id = auth.uid();

  if not found or v_runner.role <> 'flexrunner' or not v_runner.is_id_verified then
    raise exception using message = 'A verified FlexRunner profile is required.';
  end if;

  if p_status is null or p_status not in ('picked_up', 'delivered') then
    raise exception using message = 'Invalid delivery status.';
  end if;

  select delivery.status into v_current_status
  from public.flexrunner_deliveries as delivery
  where delivery.id = p_delivery_id and delivery.runner_id = v_runner.id
  for update;

  if not found
    or (p_status = 'picked_up' and v_current_status <> 'assigned')
    or (p_status = 'delivered' and v_current_status <> 'picked_up') then
    raise exception using message = 'Delivery status cannot move to that step.';
  end if;

  if p_status = 'picked_up' and not exists (
    select 1
    from public.flexrunner_deliveries as delivery
    join public.qr_handoffs as handoff on handoff.rental_id = delivery.rental_id
    where delivery.id = p_delivery_id
      and handoff.pickup_verified_at is not null
      and handoff.before_photo_url is not null
  ) then
    raise exception using message = 'Verify the pickup QR and condition photo first.';
  end if;

  update public.flexrunner_deliveries
    set status = p_status
    where id = p_delivery_id;
end;
$$;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'flexrunner_deliveries'
    ) then
    execute 'alter publication supabase_realtime add table public.flexrunner_deliveries';
  end if;
end
$$;

revoke all on function public.list_my_rental_handoffs()
  from public, anon;
revoke all on function public.get_rental_handoff_qr(uuid)
  from public, anon;
revoke all on function public.verify_rental_handoff(uuid, text, text, text)
  from public, anon;
revoke all on function public.list_my_flexrunner_deliveries()
  from public, anon;
revoke all on function public.accept_flexrunner_delivery(uuid)
  from public, anon;
revoke all on function public.update_flexrunner_delivery_status(uuid, text)
  from public, anon;

grant execute on function public.list_my_rental_handoffs()
  to authenticated;
grant execute on function public.get_rental_handoff_qr(uuid)
  to authenticated;
grant execute on function public.verify_rental_handoff(uuid, text, text, text)
  to authenticated;
grant execute on function public.list_my_flexrunner_deliveries()
  to authenticated;
grant execute on function public.accept_flexrunner_delivery(uuid)
  to authenticated;
grant execute on function public.update_flexrunner_delivery_status(uuid, text)
  to authenticated;