"""Kynetix releases on Google Play, from the terminal.

Uses the Google Play Developer API (androidpublisher v3) with the service
account key kept OUTSIDE the repo (Documents\\Kynetix-private). The key is
read, never printed.

  python tool/play/publish.py --check
      Read only: shows every track and its releases. Changes nothing.

  python tool/play/publish.py --upload PATH.aab --track alpha --notes "..."
      Uploads the bundle and releases it on the track (alpha = closed testing).
      Add --rollout 0.2 for a 20% staged rollout (production only).

  python tool/play/publish.py --promote alpha production --rollout 0.2
      Takes the newest release on one track and releases it on another.

  python tool/play/publish.py --rollout-to 1.0 --track production
      Moves a staged production rollout to a new percentage (1.0 = everyone).

Every change is shown first and needs a typed "yes" (or --yes).
Nothing is committed unless you confirm; a cancelled run deletes its edit.
"""
import argparse
import os
import sys

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

PACKAGE = 'com.kynetix.app'
LANG = 'en-IN'
KEY = os.path.join(os.path.expanduser('~'), 'Documents', 'Kynetix-private', 'play-service-account.json')
SCOPES = ['https://www.googleapis.com/auth/androidpublisher']
TRACK_NAMES = {'alpha': 'Closed testing', 'beta': 'Open testing', 'internal': 'Internal testing', 'production': 'Production'}


def service():
    if not os.path.exists(KEY):
        sys.exit(f'Service account key not found at {KEY}')
    creds = service_account.Credentials.from_service_account_file(KEY, scopes=SCOPES)
    return build('androidpublisher', 'v3', credentials=creds, cache_discovery=False, static_discovery=False)


def describe(release):
    codes = ', '.join(release.get('versionCodes', [])) or '-'
    frac = release.get('userFraction')
    pct = f' at {round(frac * 100)}%' if frac else ''
    return f"{release.get('name', '(no name)')}  [codes {codes}]  {release.get('status')}{pct}"


def show_tracks(edits, edit_id):
    tracks = edits.tracks().list(packageName=PACKAGE, editId=edit_id).execute().get('tracks', [])
    for t in tracks:
        name = TRACK_NAMES.get(t['track'], t['track'])
        rels = t.get('releases', [])
        print(f"\n{name} ({t['track']})")
        if not rels:
            print('  no releases')
        for r in rels:
            print('  ' + describe(r))


def confirm(args, lines):
    print('\nAbout to change Google Play:')
    for line in lines:
        print('  ' + line)
    if args.yes:
        return True
    return input('\nType yes to commit: ').strip().lower() == 'yes'


def notes_block(text):
    return [{'language': LANG, 'text': text}] if text else []


def main():
    p = argparse.ArgumentParser(description='Kynetix Google Play releases')
    p.add_argument('--check', action='store_true', help='read only: list tracks and releases')
    p.add_argument('--upload', metavar='AAB')
    p.add_argument('--track', default='alpha')
    p.add_argument('--notes', default='')
    p.add_argument('--name', default='')
    p.add_argument('--rollout', type=float, help='staged rollout fraction, production only (0 < x < 1)')
    p.add_argument('--promote', nargs=2, metavar=('FROM', 'TO'))
    p.add_argument('--rollout-to', type=float, help='set a production rollout fraction (1.0 = everyone)')
    p.add_argument('--yes', action='store_true', help='skip the confirmation prompt')
    args = p.parse_args()

    if args.rollout is not None and not 0 < args.rollout < 1:
        sys.exit('--rollout must be between 0 and 1, for example 0.2 for 20%')

    edits = service().edits()
    edit_id = edits.insert(packageName=PACKAGE, body={}).execute()['id']
    committed = False
    try:
        if args.check or not (args.upload or args.promote or args.rollout_to is not None):
            show_tracks(edits, edit_id)
            return

        if args.upload:
            if not os.path.exists(args.upload):
                sys.exit(f'No such file: {args.upload}')
            print(f'Uploading {os.path.basename(args.upload)} ...')
            media = MediaFileUpload(args.upload, mimetype='application/octet-stream', resumable=True)
            bundle = edits.bundles().upload(packageName=PACKAGE, editId=edit_id, media_body=media).execute()
            code = str(bundle['versionCode'])
            release = {
                'name': args.name or code,
                'versionCodes': [code],
                'releaseNotes': notes_block(args.notes),
                'status': 'completed',
            }
            if args.rollout:
                release.update(status='inProgress', userFraction=args.rollout)
            lines = [f"Release version code {code} as \"{release['name']}\" on {TRACK_NAMES.get(args.track, args.track)}",
                     f"Status: {release['status']}" + (f" at {round(args.rollout * 100)}%" if args.rollout else ''),
                     f"Notes ({LANG}): {args.notes or '(none)'}"]
            edits.tracks().update(packageName=PACKAGE, editId=edit_id, track=args.track,
                                  body={'track': args.track, 'releases': [release]}).execute()

        elif args.promote:
            src, dst = args.promote
            rels = edits.tracks().get(packageName=PACKAGE, editId=edit_id, track=src).execute().get('releases', [])
            if not rels:
                sys.exit(f'No release on {src} to promote')
            newest = max(rels, key=lambda r: max(int(c) for c in r.get('versionCodes', ['0'])))
            release = {k: newest[k] for k in ('name', 'versionCodes', 'releaseNotes') if k in newest}
            release['status'] = 'completed'
            if args.rollout:
                release.update(status='inProgress', userFraction=args.rollout)
            lines = [f"Promote {describe(newest)}",
                     f"from {TRACK_NAMES.get(src, src)} to {TRACK_NAMES.get(dst, dst)}",
                     f"Status: {release['status']}" + (f" at {round(args.rollout * 100)}%" if args.rollout else '')]
            edits.tracks().update(packageName=PACKAGE, editId=edit_id, track=dst,
                                  body={'track': dst, 'releases': [release]}).execute()

        else:  # --rollout-to
            frac = args.rollout_to
            if not 0 < frac <= 1:
                sys.exit('--rollout-to must be between 0 and 1')
            rels = edits.tracks().get(packageName=PACKAGE, editId=edit_id, track=args.track).execute().get('releases', [])
            live = [r for r in rels if r.get('status') == 'inProgress']
            if not live:
                sys.exit(f'No staged rollout in progress on {args.track}')
            r = live[0]
            r = {k: r[k] for k in ('name', 'versionCodes', 'releaseNotes') if k in r}
            if frac >= 1:
                r['status'] = 'completed'
            else:
                r.update(status='inProgress', userFraction=frac)
            lines = [f"Set {describe(live[0])} on {args.track} to {round(frac * 100)}%"]
            edits.tracks().update(packageName=PACKAGE, editId=edit_id, track=args.track,
                                  body={'track': args.track, 'releases': [r]}).execute()

        if not confirm(args, lines):
            print('Cancelled. Nothing changed on Google Play.')
            return
        edits.commit(packageName=PACKAGE, editId=edit_id).execute()
        committed = True
        print('Committed. Google reviews the change before it goes out; see Publishing overview.')
    finally:
        if not committed:
            try:
                edits.delete(packageName=PACKAGE, editId=edit_id).execute()
            except Exception:
                pass


if __name__ == '__main__':
    from googleapiclient.errors import HttpError
    try:
        main()
    except HttpError as e:
        if e.resp.status == 403:
            sys.exit('Google Play says this service account has no access to Kynetix yet. '
                     'Invite it in Play Console > Users and permissions with the Kynetix app '
                     'permissions. New access can take up to 24 hours to switch on.')
        sys.exit(f'Google Play API error {e.resp.status}: {e._get_reason()}')
