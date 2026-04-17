import io
path = r'c:\Users\Dhruv\Desktop\Kynetix\kynetix_ui\lib\screens\day_detail_screen.dart'
with io.open(path, 'r', encoding='utf-8') as f:
    text = f.read()
text = text.replace("final wheyMeta = f'{", "final wheyMeta = '${")
text = text.replace("final eggMeta = f'{", "final eggMeta = '${")
with io.open(path, 'w', encoding='utf-8') as f:
    f.write(text)
