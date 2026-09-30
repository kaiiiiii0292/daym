alter table public.rentals
  add column duration_count integer not null default 1
    check (duration_count > 0),
  add column protection_tier text not null default 'standard'
    check (protection_tier in ('none', 'standard', 'plus')),
  add column platform_commission_amount numeric(10, 2) not null default 0
    check (platform_commission_amount >= 0),
  add column payment_status text not null default 'pending'
    check (payment_status in ('pending', 'paid', 'failed', 'cancelled')),
  add column payment_reference text;

comment on column public.rentals.duration_count is
  'Number of hours or days selected by the borrower.';
comment on column public.rentals.protection_tier is
  'none = 0x, standard = 1x, plus = 2x the item protection_fee_php.';
comment on column public.rentals.platform_commission_amount is
  '12% of the base rental amount in PHP, deducted from the owner payout.';
comment on column public.rentals.payment_status is
  'Set to paid only after a trusted GCash/Maya payment-provider webhook confirms settlement.';
comment on column public.rentals.payment_reference is
  'Payment-provider reference, written by trusted backend code only.';

create or replace function public.checkout_equipment_rental(
  p_item_id uuid,
  p_duration_type text,
  p_duration_count integer,
  p_protection_tier text,
  p_payment_method text,
  p_delivery_requested boolean default false,
  p_dropoff_classroom text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_borrower public.users%rowtype;
  v_item public.equipment_items%rowtype;
  v_rental_id uuid;
  v_base_amount numeric(10, 2);
  v_protection_fee numeric(10, 2);
  v_commission_rate numeric(4, 3) := 0.120;
  v_commission_amount numeric(10, 2);
  v_delivery_fee numeric(10, 2) := 80.00;
  v_due_timestamp timestamptz;
begin
  if auth.uid() is null then
    raise exception using message = 'Sign in before requesting a rental.';
  end if;

  select profile.*
    into v_borrower
    from public.users as profile
    where profile.auth_user_id = auth.uid()
    for update;

  if not found
    or v_borrower.role <> 'borrower'
    or not v_borrower.is_id_verified then
    raise exception using message = 'A verified borrower profile is required.';
  end if;

  if p_duration_type is null or p_duration_type not in ('hourly', 'daily') then
    raise exception using message = 'Choose an hourly or daily rental.';
  end if;

  if p_duration_count is null
    or p_duration_count < 1
    or (p_duration_type = 'hourly' and p_duration_count > 24)
    or (p_duration_type = 'daily' and p_duration_count > 30) then
    raise exception using message = 'Choose a valid rental duration.';
  end if;

  if p_protection_tier is null
    or p_protection_tier not in ('none', 'standard', 'plus') then
    raise exception using message = 'Choose a valid protection tier.';
  end if;

  if p_payment_method is null or p_payment_method not in ('GCash', 'Maya') then
    raise exception using message = 'Choose GCash or Maya.';
  end if;

  if coalesce(p_delivery_requested, false)
    and nullif(trim(p_dropoff_classroom), '') is null then
    raise exception using message = 'Enter the classroom for FlexRunner delivery.';
  end if;

  select item.*
    into v_item
    from public.equipment_items as item
    where item.id = p_item_id
      and item.is_available
    for update;

  if not found then
    raise exception using message = 'This item is no longer available.';
  end if;

  if v_item.owner_id = v_borrower.id then
    raise exception using message = 'You cannot rent your own listing.';
  end if;

  if exists (
    select 1
    from public.rentals as existing
    where existing.item_id = v_item.id
      and existing.status in ('requested', 'confirmed', 'active')
  ) then
    raise exception using message = 'A rental request is already in progress for this item.';
  end if;

  v_base_amount := round(
    case p_duration_type
      when 'hourly' then v_item.hourly_rate_php
      else v_item.daily_rate_php
    end * p_duration_count,
    2
  );
  v_protection_fee := round(
    v_item.protection_fee_php * case p_protection_tier
      when 'none' then 0
      when 'plus' then 2
      else 1
    end,
    2
  );
  v_commission_amount := round(v_base_amount * v_commission_rate, 2);
  v_due_timestamp := now() + case p_duration_type
    when 'hourly' then p_duration_count * interval '1 hour'
    else p_duration_count * interval '1 day'
  end;

  insert into public.rentals (
    item_id,
    borrower_id,
    duration_type,
    duration_count,
    base_amount,
    platform_commission,
    platform_commission_amount,
    protection_tier,
    protection_fee,
    late_fee,
    payment_method,
    payment_status,
    status,
    due_timestamp
  ) values (
    v_item.id,
    v_borrower.id,
    p_duration_type,
    p_duration_count,
    v_base_amount,
    v_commission_rate,
    v_commission_amount,
    p_protection_tier,
    v_protection_fee,
    0,
    p_payment_method,
    'pending',
    'requested',
    v_due_timestamp
  ) returning id into v_rental_id;

  if coalesce(p_delivery_requested, false) then
    insert into public.flexrunner_deliveries (
      rental_id,
      pickup_building,
      dropoff_classroom,
      delivery_fee,
      platform_cut,
      status
    ) values (
      v_rental_id,
      v_item.campus_building,
      trim(p_dropoff_classroom),
      v_delivery_fee,
      round(v_delivery_fee * v_commission_rate, 2),
      'open'
    );
  end if;

  update public.equipment_items
    set is_available = false
    where id = v_item.id;

  return v_rental_id;
end;
$$;

revoke all on function public.request_equipment_rental(uuid, text, text)
  from public, anon, authenticated;
revoke all on function public.checkout_equipment_rental(
  uuid, text, integer, text, text, boolean, text
) from public, anon;
grant execute on function public.checkout_equipment_rental(
  uuid, text, integer, text, text, boolean, text
) to authenticated;