"""Logical backup of the Kynetix production database, no Docker or pg_dump.

Reads every table through the Supabase CLI (`supabase db query --linked`,
Management API, uses the CLI login on this PC) and writes one gzipped JSON
file per run to Documents/Kynetix-private/backups/. Keeps the newest
--keep files (default 14). Read-only against production.

What is in a backup:
- every table in the public schema (all rows)
- auth.users and auth.identities (so accounts and Google links can be restored)
- storage.buckets and storage.objects metadata (file list, not file bytes)

The schema itself is not dumped: it lives in git (supabase/migrations).
Restore with tools/ops/restore_db.py. See docs/DISASTER_RECOVERY.md.

Usage: python tools/ops/backup_db.py [--keep 14] [--out DIR]
"""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import json
import subprocess
import sys
from pathlib import Path

PROJECT_REF = 'sjrcqvqhycxtwwbivizy'
PAGE = 500
EXTRA = [('auth', 'users'), ('auth', 'identities'), ('storage', 'buckets'), ('storage', 'objects')]


def query(sql: str) -> list[dict]:
    out = subprocess.run(
        ['supabase', 'db', 'query', '--agent', 'no', '--linked', '--project-ref', PROJECT_REF, '--output-format', 'json', sql],
        capture_output=True, text=True, encoding='utf-8', timeout=180,
    )
    text = out.stdout
    if out.returncode != 0:
        raise RuntimeError(f'query failed (exit {out.returncode}): {(out.stderr or text)[-400:]}')
    # With --agent no the CLI prints the rows as one JSON array (stdout may
    # also carry notices before it).
    i = text.find('[')
    while i >= 0:
        try:
            obj, _ = json.JSONDecoder().raw_decode(text, i)
        except json.JSONDecodeError:
            i = text.find('[', i + 1)
            continue
        if isinstance(obj, list):
            return obj
        i = text.find('[', i + 1)
    raise RuntimeError(f'no rows in query output: {text[-400:]}')


def table_rows(schema: str, table: str) -> list[dict]:
    rows: list[dict] = []
    offset = 0
    while True:
        page = query(
            f'select coalesce(json_agg(t), \'[]\'::json) as j from '
            f'(select * from "{schema}"."{table}" order by 1 limit {PAGE} offset {offset}) t'
        )
        chunk = page[0]['j'] if page else []
        if isinstance(chunk, str):
            chunk = json.loads(chunk)
        rows.extend(chunk)
        if len(chunk) < PAGE:
            return rows
        offset += PAGE


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--keep', type=int, default=14)
    ap.add_argument('--out', default=str(Path.home() / 'Documents' / 'Kynetix-private' / 'backups'))
    a = ap.parse_args()
    out_dir = Path(a.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    tables = [('public', r['table_name']) for r in query(
        "select table_name from information_schema.tables "
        "where table_schema = 'public' and table_type = 'BASE TABLE' order by table_name"
    )] + EXTRA

    started = dt.datetime.now(dt.timezone.utc)
    backup = {'project_ref': PROJECT_REF, 'taken_at': started.isoformat(), 'format': 1, 'tables': {}}
    for schema, table in tables:
        rows = table_rows(schema, table)
        backup['tables'][f'{schema}.{table}'] = rows
        print(f'  {schema}.{table}: {len(rows)} rows')

    name = f'kynetix-{started.strftime("%Y%m%d-%H%M%S")}.json.gz'
    path = out_dir / name
    tmp = path.with_suffix('.tmp')
    with gzip.open(tmp, 'wt', encoding='utf-8') as f:
        json.dump(backup, f, ensure_ascii=False, default=str)
    tmp.replace(path)
    total = sum(len(v) for v in backup['tables'].values())
    print(f'Wrote {path} ({path.stat().st_size // 1024} KB, {total} rows, {len(tables)} tables)')

    old = sorted(out_dir.glob('kynetix-*.json.gz'))[:-a.keep] if a.keep > 0 else []
    for p in old:
        p.unlink()
    if old:
        print(f'Removed {len(old)} old backup(s); keeping {a.keep}.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001
        print(f'BACKUP FAILED: {e}', file=sys.stderr)
        sys.exit(1)
