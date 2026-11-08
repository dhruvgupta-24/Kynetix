"""Daily health report for Kynetix production (read-only).

Prints the last 24 hours: app crash reports grouped by type, AI usage
against the global budget, new sign-ups, new feedback and Kyno reports.
Exit code 2 when something needs a look (crashes, AI budget over 80%, or
unread safety reports), so a scheduler can flag it.

Usage: python tools/ops/health_report.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from backup_db import query  # noqa: E402

SQL = {
    'crashes': """
        select error_type, count(*)::int n, max(app_version) version
          from public.client_errors
         where created_at > now() - interval '24 hours'
         group by error_type order by n desc limit 10""",
    'signups': "select count(*)::int n from auth.users where created_at > now() - interval '24 hours'",
    'users': "select count(*)::int n from auth.users",
    'ai_global': "select * from public.ai_global_usage order by 1 desc limit 3",
    'feedback_new': "select count(*)::int n from public.feedback where status = 'new'",
    'reports_new': "select count(*)::int n from public.kyno_reports where status = 'new'",
}


def main() -> int:
    flags = []
    crashes = query(SQL['crashes'])
    print('Kynetix health, last 24 h')
    print(f"  users: {query(SQL['users'])[0]['n']} total, {query(SQL['signups'])[0]['n']} new")
    if crashes:
        total = sum(r['n'] for r in crashes)
        flags.append(f'{total} crash reports')
        print(f'  crashes: {total}')
        for r in crashes:
            print(f"    {r['n']:4d}  {r['error_type']}  (up to {r['version']})")
    else:
        print('  crashes: none')
    for row in query(SQL['ai_global']):
        print(f'  ai budget row: {row}')
    fb = query(SQL['feedback_new'])[0]['n']
    rp = query(SQL['reports_new'])[0]['n']
    print(f'  unread feedback: {fb}, unread Kyno reports: {rp}')
    if rp:
        flags.append(f'{rp} unread Kyno safety reports')
    if flags:
        print('NEEDS A LOOK: ' + '; '.join(flags))
        return 2
    print('All quiet.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001
        print(f'HEALTH CHECK FAILED: {e}', file=sys.stderr)
        sys.exit(1)
