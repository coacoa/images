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
  <!-- Cloudflare Web Analytics -->
  <script type='module' src='https://static.cloudflareinsights.com/beacon.min.js' data-cf-beacon='{"token": "c0e482c867484a3fa0c49fe8b8dfd8b4"}'></script>
  <!-- End Cloudflare Web Analytics -->
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
