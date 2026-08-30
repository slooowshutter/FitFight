-- Large initial HealthKit histories remain one resumable private object. The
-- processor validates once, then streams raw events into bounded SQL batches.
update storage.buckets
set file_size_limit = 536870912
where id = 'provider-inbox';

alter table private.provider_uploads
  drop constraint provider_uploads_size,
  add constraint provider_uploads_size check (
    expected_byte_size between 1 and 536870912
  ),
  drop constraint provider_uploads_actual_size,
  add constraint provider_uploads_actual_size check (
    actual_byte_size is null or actual_byte_size between 1 and 536870912
  );
