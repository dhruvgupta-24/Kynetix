"""Builds Kynetix's auth email templates from one layout.

Run:  python supabase/templates/build_emails.py
Writes one .html per email next to this file. They mirror the app's
Graphite Ember look: near-black page, one raised card, the Kynetix
wordmark with its ember full stop, the code set large like the app's numbers, and a solid white
pill for the one action. Tables and inline styles only, so Gmail, Outlook
and Apple Mail render them the same. Supabase fills {{ .Token }},
{{ .ConfirmationURL }} and {{ .NewEmail }}.
"""

from pathlib import Path

OUT = Path(__file__).parent

BG = '#0B0B0C'
CARD = '#161617'
INSET = '#0E0E0F'
HAIR = '#242425'
EDGE = '#2B2B2C'
TEXT = '#F2F1EC'
DIM = '#A6A5A0'
MUTED = '#7B7A76'
EMBER = '#FF6A3D'
FONT = "'Inter Tight','Inter',-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"


def page(*, title, preheader, kicker, heading, intro, body, why):
    return f"""<!doctype html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark">
<meta name="supported-color-schemes" content="dark">
<title>{title}</title>
</head>
<body style="margin:0;padding:0;background:{BG};" bgcolor="{BG}">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:{BG};">{preheader}&#8199;&#65279;&#847;&#8199;&#65279;&#847;&#8199;&#65279;&#847;</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="{BG}" style="background:{BG};">
<tr><td align="center" style="padding:40px 16px 48px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:480px;">

<tr><td style="padding:0 4px 28px;font-family:{FONT};font-size:24px;line-height:24px;font-weight:700;letter-spacing:-0.8px;color:{TEXT};">Kynetix<span style="color:{EMBER};">.</span></td></tr>

<tr><td bgcolor="{CARD}" style="background:{CARD};border:1px solid {HAIR};border-radius:22px;padding:32px 28px 30px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
    <tr><td style="font-family:{FONT};font-size:13px;line-height:18px;font-weight:600;color:{EMBER};padding-bottom:10px;">{kicker}</td></tr>
    <tr><td style="font-family:{FONT};font-size:26px;line-height:31px;font-weight:700;letter-spacing:-0.8px;color:{TEXT};padding-bottom:12px;">{heading}</td></tr>
    <tr><td style="font-family:{FONT};font-size:15px;line-height:23px;color:{DIM};padding-bottom:24px;">{intro}</td></tr>
    {body}
  </table>
</td></tr>

<tr><td style="padding:24px 8px 0;font-family:{FONT};font-size:12px;line-height:19px;color:{MUTED};">
  {why}
  <br><br>
  <span style="color:{DIM};font-weight:600;">Kynetix</span>&nbsp;&nbsp;Real food. Real lifts.
</td></tr>

</table>
</td></tr>
</table>
</body>
</html>
"""


def code_block(note):
    return f"""<tr><td align="center" bgcolor="{INSET}" style="background:{INSET};border:1px solid {EDGE};border-radius:16px;padding:22px 12px;">
      <div style="font-family:{FONT};font-size:38px;line-height:44px;font-weight:700;letter-spacing:12px;color:{TEXT};padding-left:12px;font-variant-numeric:tabular-nums;">{{{{ .Token }}}}</div>
    </td></tr>
    <tr><td align="center" style="font-family:{FONT};font-size:12.5px;line-height:18px;color:{MUTED};padding:12px 0 0;">{note}</td></tr>"""


def button(label, top=24):
    return f"""<tr><td style="padding-top:{top}px;">
      <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
        <td bgcolor="{TEXT}" style="background:{TEXT};border-radius:100px;">
          <a href="{{{{ .ConfirmationURL }}}}" style="display:inline-block;padding:14px 26px;font-family:{FONT};font-size:15px;line-height:18px;font-weight:600;color:{BG};text-decoration:none;border-radius:100px;">{label}</a>
        </td>
      </tr></table>
    </td></tr>"""


def divider_text(text):
    return f"""<tr><td style="padding-top:24px;"><div style="height:1px;line-height:1px;background:{HAIR};font-size:0;">&nbsp;</div></td></tr>
    <tr><td style="font-family:{FONT};font-size:14px;line-height:21px;color:{DIM};padding-top:20px;">{text}</td></tr>"""


def small(text, top=16):
    return f"""<tr><td style="font-family:{FONT};font-size:12.5px;line-height:19px;color:{MUTED};padding-top:{top}px;">{text}</td></tr>"""


TEMPLATES = {
    'confirmation': dict(
        subject="Your Kynetix code is here",
        title='Your Kynetix code',
        preheader="Here's your code: {{ .Token }}. Pop it in and you're set.",
        kicker='Almost in',
        heading="Here's your code",
        intro="Pop this into Kynetix and you're in. We'll sort out your calories and protein from there.",
        body=code_block('Good for the next hour')
        + divider_text('Reading this on your phone? Skip the typing.')
        + button('Let me in', top=14),
        why="Didn't sign up for Kynetix? No worries, just ignore this and nothing happens.",
    ),
    'recovery': dict(
        subject="Let's get you back in",
        title='Reset your Kynetix password',
        preheader='Forgot your password? Happens. Set a new one in ten seconds.',
        kicker='Password reset',
        heading='Forgot it? Happens.',
        intro='Tap below on the phone with Kynetix and pick a new one. Takes about ten seconds.',
        body=button('Set a new password', top=0)
        + small("Link's good for an hour and works once. Your meals, lifts and streaks aren't going anywhere."),
        why="Didn't ask for this? Ignore it and your password stays exactly as it is.",
    ),
    'email_change': dict(
        subject='Quick check on your new email',
        title='Confirm your new email',
        preheader="You're moving Kynetix to {{ .NewEmail }}. Confirm it's you.",
        kicker='New email',
        heading='Is this you?',
        intro="You're moving your Kynetix account to <span style=\"color:#F2F1EC;\">{{ .NewEmail }}</span>. Drop this code in the app, or just tap the button.",
        body=code_block('Good for the next hour') + button("Yep, that's me"),
        why="Wasn't you? Ignore this and nothing changes.",
    ),
    'magic_link': dict(
        subject='Your way back into Kynetix',
        title='Your Kynetix sign-in',
        preheader="One tap and you're in. Or use the code {{ .Token }}.",
        kicker='Sign in',
        heading="One tap and you're in",
        intro="Hit the button on your phone, or use the code below if that's easier.",
        body=button('Sign me in', top=0) + divider_text('Or type this in') + '<tr><td style="padding-top:12px;"></td></tr>' + code_block('Good for the next hour'),
        why="Didn't try to sign in? Ignore this, your account's safe.",
    ),
    'reauthentication': dict(
        subject='Quick security check',
        title='Your Kynetix verification code',
        preheader="Your code is {{ .Token }}. Just making sure it's you.",
        kicker='Quick check',
        heading="Just making sure it's you",
        intro='Pop this code into Kynetix to carry on.',
        body=code_block('Good for the next hour'),
        why="Not you? Ignore this, and maybe change your password just in case.",
    ),
    'invite': dict(
        subject="Someone thinks you'd like Kynetix",
        title="You're invited to Kynetix",
        preheader='Real food, real lifts, zero spreadsheets.',
        kicker="You're invited",
        heading='Come train with us',
        intro='Log food the way you actually eat it, track every set, and get targets that fit your week. No spreadsheets, no guilt.',
        body=button("I'm in", top=0),
        why='Not expecting this? Just ignore it.',
    ),
}

def main():
    for name, t in TEMPLATES.items():
        html = page(**{k: t[k] for k in ('title', 'preheader', 'kicker', 'heading', 'intro', 'body', 'why')})
        (OUT / f'{name}.html').write_text(html, encoding='utf-8', newline='\n')
    print('wrote', ', '.join(f'{n}.html' for n in TEMPLATES))


if __name__ == '__main__':
    main()
