-- Nexo: lets a second device find a dataset of the same person by name.
-- Synthetic lab only. Unnamed datasets (server self-tests) are not listed.
begin;

alter table nexo_sync_lab_private.datasets
  add column label text check (label is null or length(label) between 1 and 60);

create function public.nexo_sync_lab_set_label(p_dataset_id uuid, p_label text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_label is null or length(trim(p_label)) not between 1 and 60 then
    raise exception using errcode = '22023', message = 'invalid_label';
  end if;
  update nexo_sync_lab_private.datasets set label = trim(p_label)
    where id = p_dataset_id and owner_id = v_user;
  if not found then
    raise exception using errcode = '42501', message = 'dataset_unavailable';
  end if;
end;
$$;

create function public.nexo_sync_lab_list_datasets()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', d.id, 'epoch', d.epoch, 'label', d.label, 'revision', d.revision,
      'created_at', d.created_at,
      'devices', (select count(*) from nexo_sync_lab_private.devices v
        where v.dataset_id = d.id and v.revoked_at is null))
      order by d.created_at desc)
    from nexo_sync_lab_private.datasets d
    where d.owner_id = v_user and d.label is not null), '[]'::jsonb);
end;
$$;

revoke all on function public.nexo_sync_lab_set_label(uuid, text) from public, anon, authenticated;
revoke all on function public.nexo_sync_lab_list_datasets() from public, anon, authenticated;
grant execute on function public.nexo_sync_lab_set_label(uuid, text) to authenticated;
grant execute on function public.nexo_sync_lab_list_datasets() to authenticated;

notify pgrst, 'reload schema';
commit;
