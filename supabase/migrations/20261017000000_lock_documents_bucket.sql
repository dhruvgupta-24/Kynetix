-- The `documents` bucket predates Kynetix's storage needs: the app never reads
-- or writes it, yet it was public and carried a policy letting anyone with the
-- anon key list, upload, overwrite and delete objects in it.
-- Lock it down without touching the existing files: make the bucket private
-- and drop the open policy. With no policy left, only the service role (the
-- dashboard and server code) can reach it.

drop policy if exists "Allow all access to documents bucket" on storage.objects;

update storage.buckets set public = false where id = 'documents';
