"""Light live stress + security probe against the Kynetix Supabase backend.

Safe by design:
- Signs up a fresh throwaway account (kynetix.app+stress-<ts>@gmail.com) and
  deletes it at the end through the real delete-account function, so every
  row it wrote goes away. If sign-up needs email confirmation it falls back
  to the Play reviewer account and runs READ-ONLY (no writes, no AI calls
  beyond the rate-limit probe).
- Never prints keys, tokens or passwords.
- Load is capped: --workers (default 50) for --seconds (default 120).
- AI calls: one burst of --ai-burst (default 14) tiny weekly_summary
  requests to prove the per-user limit holds under concurrency.

Usage:  python tools/ops/stress_test.py [--workers 50] [--seconds 120]
"""

from __future__ import annotations

import argparse
import asyncio
import json
import re
import secrets
import statistics
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[2]
SECRETS = ROOT / 'kynetix_ui' / 'lib' / 'config' / 'supabase_secrets.dart'
REVIEWER = Path.home() / 'Documents' / 'Kynetix-private' / 'reviewer-account.txt'

USER_TABLES = [
    'profiles', 'day_logs', 'body_metrics', 'workout_sessions', 'workout_splits',
    'user_achievements', 'user_eating_patterns', 'user_insights_cache', 'user_meal_contexts',
    'user_nutrition_memory', 'user_quick_adds', 'feedback', 'kyno_reports', 'app_events',
    'client_errors', 'guardian_consents', 'user_openai_links', 'openai_device_auth_sessions',
]
SERVICE_ONLY = ['ai_usage', 'ai_global_usage', 'system_flags', 'user_insert_rate',
                'client_error_rate', 'profiles_backup_pre_rollback']


def load_config() -> tuple[str, str]:
    src = SECRETS.read_text(encoding='utf-8')
    url = re.search(r"url\s*=\s*'([^']+)'", src).group(1).rstrip('/')
    key = re.search(r"anonKey\s*=\s*'([^']+)'", src).group(1)
    return url, key


class Probe:
    def __init__(self, url: str, anon: str):
        self.url, self.anon = url, anon
        self.results: list[tuple[str, bool, str]] = []

    def check(self, name: str, ok: bool, detail: str = '') -> None:
        self.results.append((name, ok, detail))
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}{' - ' + detail if detail else ''}")

    def h(self, token: str | None = None, extra: dict | None = None) -> dict:
        d = {'apikey': self.anon, 'Authorization': f'Bearer {token or self.anon}'}
        d.update(extra or {})
        return d


async def sign_up(c: httpx.AsyncClient, p: Probe) -> tuple[str | None, str | None, str]:
    email = f'kynetix.app+stress-{int(time.time())}@gmail.com'
    pw = secrets.token_urlsafe(24)
    r = await c.post(f'{p.url}/auth/v1/signup', headers=p.h(), json={'email': email, 'password': pw})
    if r.status_code == 200 and r.json().get('access_token'):
        j = r.json()
        return j['access_token'], j['user']['id'], 'fresh'
    return None, None, f'signup {r.status_code}'


async def sign_in_reviewer(c: httpx.AsyncClient, p: Probe) -> tuple[str | None, str | None]:
    txt = REVIEWER.read_text(encoding='utf-8')
    email = re.search(r'Email:\s*(\S+)', txt).group(1)
    pw = re.search(r'Password:\s*(\S+)', txt).group(1)
    r = await c.post(f'{p.url}/auth/v1/token?grant_type=password', headers=p.h(),
                     json={'email': email, 'password': pw})
    if r.status_code != 200:
        return None, None
    j = r.json()
    return j['access_token'], j['user']['id']


# ── Security probes (read-only unless fresh account) ────────────────────────

async def security(c: httpx.AsyncClient, p: Probe, tok: str, uid: str, fresh: bool) -> None:
    print('\n== Security probes ==')
    rest = f'{p.url}/rest/v1'

    # 1. anon sees nothing
    leaks = []
    for t in USER_TABLES + SERVICE_ONLY:
        r = await c.get(f'{rest}/{t}?select=*&limit=1', headers=p.h())
        if r.status_code == 200 and r.json():
            leaks.append(t)
    p.check('anon key reads no user/service rows', not leaks, ','.join(leaks))

    # 2. signed-in user sees only own rows; service tables closed
    foreign = []
    for t in USER_TABLES:
        col = 'id' if t == 'profiles' else 'user_id'
        r = await c.get(f'{rest}/{t}?select={col}&{col}=neq.{uid}&limit=1', headers=p.h(tok))
        if r.status_code == 200 and r.json():
            foreign.append(t)
    p.check('user cannot read other users rows', not foreign, ','.join(foreign))
    open_service = []
    for t in SERVICE_ONLY:
        r = await c.get(f'{rest}/{t}?select=*&limit=1', headers=p.h(tok))
        if r.status_code == 200 and r.json():
            open_service.append(t)
    p.check('service-only tables closed to users', not open_service, ','.join(open_service))

    # 3. writes as someone else are refused (rows would belong to a random uuid)
    other = '00000000-0000-4000-8000-000000000001'
    r = await c.post(f'{rest}/day_logs', headers=p.h(tok, {'Prefer': 'return=minimal'}),
                     json={'user_id': other, 'date_key': '2099-01-01'})
    p.check('insert with another user_id refused', r.status_code in (401, 403), str(r.status_code))
    r = await c.post(f'{rest}/app_curators', headers=p.h(tok, {'Prefer': 'return=minimal'}),
                     json={'user_id': uid})
    p.check('user cannot make self curator', r.status_code in (401, 403), str(r.status_code))
    r = await c.post(f'{rest}/day_logs', headers=p.h(None, {'Prefer': 'return=minimal'}),
                     json={'user_id': uid, 'date_key': '2099-01-02'})
    p.check('anon cannot insert', r.status_code in (401, 403), str(r.status_code))

    # 4. storage: cross-folder upload refused, listing others empty
    r = await c.post(f'{p.url}/storage/v1/object/feedback-photos/{other}/x.png',
                     headers=p.h(tok, {'Content-Type': 'image/png'}), content=b'\x89PNG\r\n\x1a\n')
    p.check('upload into another user folder refused', r.status_code in (400, 401, 403, 404), str(r.status_code))
    r = await c.post(f'{p.url}/storage/v1/object/list/feedback-photos', headers=p.h(tok),
                     json={'prefix': '', 'limit': 100})
    names = [o.get('name') for o in (r.json() if r.status_code == 200 else [])]
    p.check('feedback-photos root lists no other users', all(n == uid for n in names), f'{len(names)} entries')
    r = await c.post(f'{p.url}/storage/v1/object/avatars/{uid}/../{other}/avatar.jpg',
                     headers=p.h(tok, {'Content-Type': 'image/jpeg'}), content=b'\xff\xd8\xff\xe0')
    p.check('path traversal upload refused', r.status_code >= 400, str(r.status_code))

    # 5. edge functions
    fn = f'{p.url}/functions/v1'
    for name in ['ai-chat-router', 'ai-meal-coach', 'delete-account', 'openai-link-status']:
        r = await c.post(f'{fn}/{name}', headers={'apikey': p.anon}, json={})
        p.check(f'{name} without JWT refused', r.status_code == 401, str(r.status_code))
    # guardian-consent runs without the gateway JWT check on purpose (the parent
    # page has no account); the teen-side 'request' action must still need one.
    r = await c.post(f'{fn}/guardian-consent', headers={'apikey': p.anon}, json={'action': 'request'})
    p.check('guardian-consent request without JWT refused', r.status_code == 401, str(r.status_code))
    r = await c.post(f'{fn}/ai-chat-router', headers=p.h(tok),
                     json={'purpose': 'coach', 'messages': [{'role': 'user', 'content': 'hi'}]})
    p.check("client cannot use internal 'coach' purpose", r.status_code == 403, str(r.status_code))
    r = await c.post(f'{fn}/ai-chat-router', headers=p.h(tok),
                     content=json.dumps({'purpose': 'weekly_summary', 'messages': [{'role': 'user', 'content': 'x' * 2_000_000}]}),
                     timeout=60)
    p.check('2 MB body refused', r.status_code in (400, 413), str(r.status_code))
    r = await c.post(f'{fn}/delete-account', headers=p.h(tok), json={})
    p.check('delete-account needs confirm phrase', r.status_code == 400, str(r.status_code))

    # 6. stored XSS payload round-trips as inert text (fresh account only)
    if fresh:
        payload = '<img src=x onerror=alert(1)><script>alert(1)</script>'
        r = await c.post(f'{rest}/day_logs?on_conflict=user_id,date_key',
                         headers=p.h(tok, {'Prefer': 'resolution=merge-duplicates,return=representation'}),
                         json={'user_id': uid, 'date_key': '2099-12-31', 'sections_json': {'note': payload}})
        back = r.json()[0]['sections_json']['note'] if r.status_code in (200, 201) and r.json() else None
        p.check('XSS payload stored verbatim (rendered as text by Flutter)', back == payload, str(r.status_code))
        r = await c.post(f'{rest}/app_events', headers=p.h(tok, {'Prefer': 'return=minimal'}),
                         json={'name': "x'; drop table app_events;--"})
        p.check('SQL-ish event name rejected by check constraint', r.status_code == 400, str(r.status_code))


# ── Load ────────────────────────────────────────────────────────────────────

async def load(c: httpx.AsyncClient, p: Probe, tok: str, uid: str, fresh: bool,
               workers: int, seconds: int) -> None:
    print(f'\n== Load: {workers} workers x {seconds}s ==')
    rest = f'{p.url}/rest/v1'
    lat: dict[str, list[float]] = defaultdict(list)
    codes: dict[str, Counter] = defaultdict(Counter)
    stop = time.monotonic() + seconds

    ops = [
        ('read_profile', 'GET', f'{rest}/profiles?select=*&id=eq.{uid}', None),
        ('read_day_logs', 'GET', f'{rest}/day_logs?select=*&user_id=eq.{uid}&order=date_key.desc&limit=30', None),
        ('read_foods', 'GET', f'{rest}/global_food_defaults?select=*&limit=50', None),
    ]
    if fresh:
        ops += [
            ('write_event', 'POST', f'{rest}/app_events', {'name': 'stress_load', 'props': {}}),
            ('upsert_day', 'POST', f'{rest}/day_logs?on_conflict=user_id,date_key', None),
        ]

    async def worker(i: int) -> None:
        n = i
        while time.monotonic() < stop:
            name, method, url, body = ops[n % len(ops)]
            n += 1
            hdr = p.h(tok)
            if name == 'upsert_day':
                hdr['Prefer'] = 'resolution=merge-duplicates,return=minimal'
                body = {'user_id': uid, 'date_key': f'2099-01-{(i % 28) + 1:02d}',
                        'sections_json': {'stress': n}}
            elif method == 'POST':
                hdr['Prefer'] = 'return=minimal'
            t0 = time.perf_counter()
            try:
                r = await c.request(method, url, headers=hdr, json=body, timeout=30)
                codes[name][r.status_code] += 1
            except Exception as e:  # noqa: BLE001
                codes[name][type(e).__name__] += 1
            lat[name].append((time.perf_counter() - t0) * 1000)

    t_start = time.monotonic()
    await asyncio.gather(*(worker(i) for i in range(workers)))
    wall = time.monotonic() - t_start
    total = sum(len(v) for v in lat.values())
    print(f'  {total} requests in {wall:.0f}s = {total / wall:.1f} req/s')
    for name, v in lat.items():
        v.sort()
        q = lambda f: v[min(len(v) - 1, int(len(v) * f))]  # noqa: E731
        print(f'  {name:14s} n={len(v):5d} p50={q(.5):6.0f}ms p95={q(.95):6.0f}ms p99={q(.99):6.0f}ms '
              f'codes={dict(codes[name])}')
    errs = sum(cnt for cs in codes.values() for k, cnt in cs.items() if not (isinstance(k, int) and k < 300))
    p.check('error rate under 1% (writes past the 600/h insert cap are dropped silently, not errors)',
            errs / max(total, 1) < 0.01, f'{errs}/{total}')
    # app_events is write-only for users, so the 600/h insert cap is not
    # observable here; the trigger drops extra rows silently and the API
    # still answers 201.


async def ai_burst(c: httpx.AsyncClient, p: Probe, tok: str, n: int) -> None:
    print(f'\n== AI rate limit: {n} concurrent requests ==')
    body = {'purpose': 'weekly_summary', 'messages': [{'role': 'user', 'content': 'Week: 3 workouts, avg 2100 kcal. One line.'}]}

    async def one() -> tuple[int, float, str]:
        t0 = time.perf_counter()
        r = await c.post(f'{p.url}/functions/v1/ai-chat-router', headers=p.h(tok), json=body, timeout=90)
        err = ''
        try:
            err = r.json().get('error', '') or ''
        except Exception:  # noqa: BLE001
            pass
        return r.status_code, (time.perf_counter() - t0) * 1000, err

    res = await asyncio.gather(*(one() for _ in range(n)))
    ok = [r for r in res if r[0] == 200]
    limited = [r for r in res if r[0] == 429]
    print(f'  statuses={dict(Counter(r[0] for r in res))} errors={dict(Counter(r[2] for r in res if r[2]))}')
    if ok:
        print(f'  ok latency p50={statistics.median(r[1] for r in ok):.0f}ms max={max(r[1] for r in ok):.0f}ms')
    p.check('concurrent burst cannot pass per-minute cap (10)', len(ok) <= 10, f'{len(ok)} ok, {len(limited)} limited')
    p.check('limited requests get 429, not 500', all(r[0] in (200, 429, 503) for r in res))


async def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--workers', type=int, default=50)
    ap.add_argument('--seconds', type=int, default=120)
    ap.add_argument('--ai-burst', type=int, default=14)
    a = ap.parse_args()
    a.workers = min(a.workers, 100)
    url, anon = load_config()
    p = Probe(url, anon)
    limits = httpx.Limits(max_connections=a.workers + 10)
    async with httpx.AsyncClient(limits=limits, timeout=30, http2=False) as c:
        tok, uid, how = await sign_up(c, p)
        fresh = tok is not None
        if not fresh:
            print(f'Fresh sign-up unavailable ({how}); using reviewer account READ-ONLY.')
            tok, uid = await sign_in_reviewer(c, p)
            if not tok:
                print('Reviewer sign-in failed.')
                return 2
        else:
            print('Signed up throwaway test account.')
        try:
            await security(c, p, tok, uid, fresh)
            await load(c, p, tok, uid, fresh, a.workers, a.seconds)
            if a.ai_burst:
                await ai_burst(c, p, tok, a.ai_burst)
        finally:
            if fresh:
                r = await c.post(f'{url}/functions/v1/delete-account', headers=p.h(tok),
                                 json={'confirm': 'DELETE'}, timeout=60)
                p.check('throwaway account deleted via delete-account', r.status_code == 200, str(r.status_code))
    fails = [r for r in p.results if not r[1]]
    print(f'\n{len(p.results) - len(fails)}/{len(p.results)} checks passed.')
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(asyncio.run(main()))
