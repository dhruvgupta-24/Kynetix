import subprocess
import codecs

with codecs.open('analyze_run.py', 'w', 'utf-8') as f:
    f.write('''import subprocess
res = subprocess.run(["flutter.bat", "analyze", "lib/screens/profile_screen.dart"], capture_output=True, text=True)
with open("analyze_clean.txt", "w", encoding="utf-8") as out:
    out.write(res.stdout)
''')
