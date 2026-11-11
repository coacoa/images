#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# ============================================================
# make_index.sh v2
# カレントディレクトリの *.html から index.html を生成する。
# v1 からの変更点：
# - リンク文字はファイル名でなく、各ページの <title> を使う（一番の変更点）
# - カテゴリはキーワード判定で正しくグルーピング（見出しはカテゴリごとに1回だけ）
# - 日付は git の最終コミット日を優先（Actions の checkout 日時で全部同じになる問題の対策）
# - index.html 自身を正しく除外（v1 は ./index.html が混入していた）
# - キーワード検索つき（小さいJSのみ、外部依存なし）
# ============================================================

OUTPUT="index.html"
TMPFILE=$(mktemp)
ROWS=$(mktemp)
trap 'rm -f "$ROWS"' EXIT

# ---------- ユーティリティ ----------

esc() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

# ページの <title> を取り出す。無ければ <h1>、それも無ければ空を返す
extract_title() {
  local f="$1" t=""
  t=$(tr '\n' ' ' < "$f" | sed -n 's/.*<title[^>]*>[[:space:]]*\([^<]*\)<.*/\1/Ip' | head -n 1)
  if [[ -z "${t//[[:space:]]/}" ]]; then
    t=$(tr '\n' ' ' < "$f" | sed -n 's/.*<h1[^>]*>[[:space:]]*\([^<]*\)<.*/\1/Ip' | head -n 1)
  fi
  # HTMLエンティティを戻して、空白を整える
  printf '%s' "$t" \
    | sed 's/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#39;/'"'"'/g' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]][[:space:]]*/ /g'
}

# ファイル名のキーワードからカテゴリを決める。「表示順|カテゴリ名」を返す
# 上から順に判定するので、具体的なものを上に置く。自由に編集してよい
category_of() {
  case "$1" in
    *nixos*|*linux*|*debian*|*alpine*)        echo "01|NixOS・Linux" ;;
    *openwrt*|*ddwrt*)                        echo "02|OpenWrt" ;;
    *network*|*lan*|*wifi*|*mdns*|*wireguard*|*nmap*|*_ap_*|*ssh*|*nat*)
                                              echo "03|ネットワーク" ;;
    *chromebook*|*asus*|*nexus*|*tpx1*|*loox*|*keyboard*|*kanata*)
                                              echo "04|デバイス" ;;
    *vim*|*emacs*|*obsidian*|*i3*|*dwm*|*sway*|*tmux*|*zellij*|*tilegata*)
                                              echo "05|エディタ・WM" ;;
    *life*|*kanji*|*calc*|*word*)             echo "06|生活・学習" ;;
    *)                                        echo "99|その他" ;;
  esac
}

# 最終更新日：git の最終コミット日を優先し、ダメならファイルの日時
last_date() {
  local f="$1" d=""
  if git rev-parse --git-dir >/dev/null 2>&1; then
    d=$(git log -1 --format=%cs -- "$f" 2>/dev/null || true)
  fi
  [[ -z "$d" ]] && d=$(date -r "$f" +%Y-%m-%d)
  printf '%s' "$d"
}

# ---------- データ収集 ----------

declare -A COUNT=()
TOTAL=0

for path in ./*.html; do
  file="${path#./}"
  [[ "$file" == "index.html" ]] && continue

  title=$(extract_title "$file")
  [[ -z "$title" ]] && title="${file%.html}"
  title="${title//$'\t'/ }"

  ord_cat=$(category_of "$file")
  ord="${ord_cat%%|*}"
  cat_name="${ord_cat#*|}"

  date=$(last_date "$file")

  printf '%s\t%s\t%s\t%s\t%s\n' "$ord" "$cat_name" "$title" "$file" "$date" >> "$ROWS"
  COUNT["$cat_name"]=$(( ${COUNT["$cat_name"]:-0} + 1 ))
  TOTAL=$((TOTAL + 1))
done

sort -t $'\t' -k1,1n -k3,3 -o "$ROWS" "$ROWS"

# ---------- HTML 生成 ----------

cat > "$TMPFILE" << EOF
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>メモ一覧</title>
  <style>
    body { font-family: sans-serif; max-width: 800px; margin: 2em auto; padding: 0 1em; line-height: 1.6; }
    h2 { border-bottom: 2px solid #ccc; padding-bottom: .2em; margin-top: 1.5em; }
    ul { list-style: none; padding-left: 0; }
    li { margin: .35em 0; }
    small { color: #777; margin-left: .5em; }
    #q { width: 100%; box-sizing: border-box; padding: .5em; font-size: 1em; margin: 1em 0; }
    a { text-decoration: none; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <h1>メモ一覧</h1>
  <p>全 ${TOTAL} 件（自動生成： $(date +%Y-%m-%d)）</p>
  <input id="q" type="search" placeholder="タイトル・ファイル名で検索">
EOF

current=""
while IFS=$'\t' read -r _ord cat_name title file date; do
  if [[ "$cat_name" != "$current" ]]; then
    [[ -n "$current" ]] && echo '</ul></section>' >> "$TMPFILE"
    printf '<section><h2>%s（%s）</h2><ul>\n' "$(esc "$cat_name")" "${COUNT[$cat_name]}" >> "$TMPFILE"
    current="$cat_name"
  fi
  printf '<li><a href="%s">%s</a><small>%s ・ %s</small></li>\n' \
    "$(esc "$file")" "$(esc "$title")" "$(esc "$file")" "$(esc "$date")" >> "$TMPFILE"
done < "$ROWS"
[[ -n "$current" ]] && echo '</ul></section>' >> "$TMPFILE"

cat >> "$TMPFILE" << 'EOF'
  <script>
    document.getElementById('q').addEventListener('input', function (e) {
      var q = e.target.value.toLowerCase();
      document.querySelectorAll('li').forEach(function (li) {
        li.style.display = li.textContent.toLowerCase().includes(q) ? '' : 'none';
      });
      document.querySelectorAll('section').forEach(function (s) {
        var visible = Array.prototype.some.call(s.querySelectorAll('li'), function (li) {
          return li.style.display !== 'none';
        });
        s.style.display = visible ? '' : 'none';
      });
    });
  </script>
</body>
</html>
EOF

mv "$TMPFILE" "$OUTPUT"
echo "完了。出力結果は $OUTPUT に保存されました（全 ${TOTAL} 件）" >&2
