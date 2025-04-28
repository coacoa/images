import os

output_dir = "out"
html_path = os.path.join(output_dir, "index.html")

svg_files = [f for f in os.listdir(output_dir) if f.endswith(".svg")]

with open(html_path, "w", encoding="utf-8") as f:
    f.write("<html><head><meta charset='utf-8'><title>SVG一覧</title></head><body>\n")
    f.write("<h1>SVG ファイル一覧</h1>\n<ul>\n")
    for svg in svg_files:
        f.write(f"<li><a href='{svg}' target='_blank'>{svg}</a></li>\n")
    f.write("</ul>\n</body></html>")
