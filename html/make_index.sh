#!/usr/bin/env bash
set -eu

OUTPUT="index.html"

echo "generate $OUTPUT"

cat > "$OUTPUT" << 'EOF'
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <title>Index</title>
</head>
<body>
<h1>HTML list</h1>
<ul>
EOF

for f in *.html; do
  [ "$f" = "index.html" ] && continue
  echo "  <li><a href=\"$f\">$f</a></li>" >> "$OUTPUT"
done

cat >> "$OUTPUT" << 'EOF'
</ul>
</body>
</html>
EOF

echo "done"

