create or replace function public.request_equipment_rental(
  p_item_id uuid,
  p_duration_type text,
  p_payment_method text
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

  if p_payment_method is null or p_payment_method not in ('GCash', 'Maya') then
    raise exception using message = 'Choose GCash or Maya.';
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

  if exists (
    select 1
    from public.rentals as existing
    where existing.item_id = v_item.id
      and existing.status in ('requested', 'confirmed', 'active')
  ) then
    raise exception using message = 'A rental request is already in progress for this item.';
  end if;

  v_due_timestamp := now() + case p_duration_type
    when 'hourly' then interval '1 hour'
    else interval '1 day'
  end;

  insert into public.rentals (
    item_id,
    borrower_id,
    duration_type,
    base_amount,
    platform_commission,
    protection_fee,
    late_fee,
    payment_method,
    status,
    due_timestamp
  ) values (
    v_item.id,
    v_borrower.id,
    p_duration_type,
    case p_duration_type
      when 'hourly' then v_item.hourly_rate_php
      else v_item.daily_rate_php
    end,
    0.120,
    v_item.protection_fee_php,
    0,
    p_payment_method,
    'requested',
    v_due_timestamp
  ) returning id into v_rental_id;

  update public.equipment_items
    set is_available = false
    where id = v_item.id;

  return v_rental_id;
end;
$$;

revoke all on function public.request_equipment_rental(uuid, text, text)
  from public, anon;
grant execute on function public.request_equipment_rental(uuid, text, text)
  to authenticated;