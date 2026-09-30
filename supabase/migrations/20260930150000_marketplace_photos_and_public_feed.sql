alter table public.equipment_items
  add column image_url text;

update public.equipment_items
set image_url = case title
  when 'Casio fx-991EX Calculator' then
    'https://images.unsplash.com/photo-1587145820266-a5951ee6f620?w=800&q=85&fit=crop'
  when 'Canon EOS DSLR Camera' then
    'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=800&q=85&fit=crop'
  when 'Wacom Drawing Tablet' then
    'https://images.unsplash.com/photo-1585790050230-5dd28404ccb9?w=800&q=85&fit=crop'
  when 'Arduino Uno Kit' then
    'https://images.unsplash.com/photo-1553406830-ef2513450d76?w=800&q=85&fit=crop'
  when 'Nursing Lab Gear' then
    'https://images.unsplash.com/photo-1584982751601-97dcc096659c?w=800&q=85&fit=crop'
  else image_url
end
where image_url is null;

create view public.equipment_marketplace with (security_barrier = true) as
select
  item.id,
  item.owner_id,
  item.title,
  item.category,
  item.hourly_rate_php,
  item.daily_rate_php,
  item.protection_fee_php,
  item.campus_building,
  item.lat,
  item.lng,
  item.is_available,
  item.image_url,
  owner.full_name as owner_name,
  owner.department as owner_department,
  owner.is_id_verified as owner_is_id_verified
from public.equipment_items as item
join public.users as owner on owner.id = item.owner_id
where item.is_available;

revoke all on public.equipment_marketplace from anon, authenticated;
grant select on public.equipment_marketplace to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'equipment_items'
    ) then
    execute 'alter publication supabase_realtime add table public.equipment_items';
  end if;
end
$$;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'flexshare-equipment',
  'flexshare-equipment',
  true,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

create policy flexshare_lender_upload_equipment_photos
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'flexshare-equipment'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and exists (
      select 1
      from public.users as owner
      where owner.auth_user_id = (select auth.uid())
        and owner.role = 'lender'
        and owner.is_id_verified
    )
  );