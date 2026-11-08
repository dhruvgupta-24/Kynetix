"""Turns a backup from backup_db.py into a restore SQL file.

Never touches a database itself. You run the SQL it writes against a
database whose schema is already in place (a fresh Supabase project after
`supabase db push`, or the old one after a bad migration), in the SQL editor
or with `supabase db query --linked -f restore.sql`.

- Rows go in with ON CONFLICT DO NOTHING, so running it on a database that
  still has some data only fills the gaps; it never overwrites.
- auth.users / auth.identities first, then public tables. Triggers and FK
  checks are off during the load (session_replication_role = replica).
- Identity columns keep their old ids (OVERRIDING SYSTEM VALUE) and their
  sequences are moved past the restored max.
- Storage file bytes are not in the backup; avatars and feedback photos come
  back empty (the rows that point at them are restored).

Usage:
  python tools/ops/restore_db.py BACKUP.json.gz OUT.sql [--only public.day_logs,public.profiles]
"""

from __future__ import annotations

import argparse
import gzip
import json
import sys

SKIP = {
    'storage.buckets', 'storage.objects',          # recreated by migrations / not restorable without bytes
    'public.user_insert_rate', 'public.client_error_rate', 'public.ai_usage',
    'public.ai_global_usage',                       # rate-limit counters: start fresh
    'public.openai_device_auth_sessions',           # short-lived login sessions
}
FIRST = ['auth.users', 'auth.identities', 'public.profiles']


def dollar(s: str) -> str:
    tag = 'kx'
    while f'${tag}$' in s:
        tag += 'x'
    return f'${tag}${s}${tag}$'


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('backup')
    ap.add_argument('out')
    ap.add_argument('--only', default='')
    a = ap.parse_args()
    with gzip.open(a.backup, 'rt', encoding='utf-8') as f:
        b = json.load(f)
    only = {t.strip() for t in a.only.split(',') if t.strip()}
    names = [t for t in FIRST if t in b['tables']] + sorted(t for t in b['tables'] if t not in FIRST)

    lines = [
        f"-- Kynetix restore from backup taken {b['taken_at']} (project {b['project_ref']}).",
        '-- Review before running. Inserts only; existing rows are left alone.',
        'begin;',
        "set local session_replication_role = 'replica';",
    ]
    for name in names:
        if (only and name not in only) or (not only and name in SKIP):
            continue
        rows = b['tables'][name]
        if not rows:
            continue
        schema, table = name.split('.')
        q = f'"{schema}"."{table}"'
        lines.append(f'-- {name}: {len(rows)} rows')
        lines.append(
            f'insert into {q} overriding system value '
            f'select * from json_populate_recordset(null::{q}, {dollar(json.dumps(rows, ensure_ascii=False))}::json) '
            f'on conflict do nothing;'
        )
        # Move identity sequences past the restored ids.
        lines.append(
            "select setval(pg_get_serial_sequence(format('%I.%I', c.table_schema, c.table_name), c.column_name), "
            f"greatest(1, (select coalesce(max(x.v), 0) from (select (to_jsonb(r) ->> c.column_name)::bigint v from {q} r) x))) "
            "from information_schema.columns c "
            f"where c.table_schema = '{schema}' and c.table_name = '{table}' and c.is_identity = 'YES';"
        )
    lines.append('commit;')
    with open(a.out, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    print(f'Wrote {a.out}: {sum(1 for l in lines if l.startswith("insert into"))} tables.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
