#!/usr/bin/env bash
set -euo pipefail

OUTPUT="index.html"
TMPFILE=$(mktemp)

echo "Generating $OUTPUT" >&2

# Create a temporary file for building the index
cat > "$TMPFILE" << 'EOF'
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <title>HTML インデックス</title>
  <style>
    body { font-family: sans-serif; }
    h2 { border-bottom: 1px solid #ccc; }
    .category { margin: 1em 0; }
    .file-info { margin-left: 1em; }
  </style>
</head>
<body>
  <h1>HTML ファイル一覧</h1>
  <p>このリストは、カレントディレクトリ内のすべてのHTMLファイルをカテゴリごとに整理して表示しています。</p>
EOF

# Process each file
while IFS= read -r -d $'\0' file; do
  # index.html をスキップ
  [[ "$file" == "index.html" ]] && continue

  # ファイル名からカテゴリを抽出（例: "memo" in "memo1.html"）
  category=$(basename "$file" .html | grep -o 'memo') || category="Other"

  # 最終編集日時を取得
  modified=$(date -r "$file" +%Y-%m-%d)

  # テンポラリーファイルに追加
  echo "  <h2>$category</h2>" >> "$TMPFILE"
  echo "  <p><strong>$file</strong> - 最終編集: $modified</p>" >> "$TMPFILE"
  echo "  <a href="$file">$file</a><br>" >> "$TMPFILE"
done < <(find . -maxdepth 1 -type f -name "*.html" -print0)

# 閉じタグを追加
cat >> "$TMPFILE" << 'EOF'
</body>
</html>
EOF

# 最終出力
mv "$TMPFILE" "$OUTPUT"
 echo "完了。出力結果は $OUTPUT に保存されました" >&2