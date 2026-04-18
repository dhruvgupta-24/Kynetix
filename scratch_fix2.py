import io

path = r'c:\Users\Dhruv\Desktop\Kynetix\kynetix_ui\lib\screens\day_detail_screen.dart'
with io.open(path, 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace('{wheyPro.toStringAsFixed(0)}g protein', '${wheyPro.toStringAsFixed(0)}g protein')
text = text.replace('{eggPro.toStringAsFixed(0)}g protein', '${eggPro.toStringAsFixed(0)}g protein')

with io.open(path, 'w', encoding='utf-8') as f:
    f.write(text)
