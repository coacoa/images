#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# ============================================================
# make_index.sh v3.2
# カレントディレクトリの *.html から index.html を生成する。
# v1 からの変更点：
# - リンク文字はファイル名でなく、各ページの <title> を使う（一番の変更点）
# - カテゴリはキーワード判定で正しくグルーピング（見出しはカテゴリごとに1回だけ）
# - 日付は git の最終コミット日を優先（Actions の checkout 日時で全部同じになる問題の対策）
# - index.html 自身を正しく除外（v1 は ./index.html が混入していた）
# - キーワード検索つき（小さいJSのみ、外部依存なし）
# v2.1 での変更点（v3 で落ちていた分を復旧）：
# - ネットワーク判定の *nat* を *_nat_* に絞る（kanataへの誤爆解消）
# - kanataをデバイスからエディタ・WMへ移し、warpdを追加
# - flake／kaden／prownosをNixOS・Linuxへ追加
# v3 での変更点：
# - 道場・ゲームのカテゴリ（00）を先頭に追加し、一覧のいちばん上に表示する
# v3.1 = v2.1 を土台に v3 の道場カテゴリを足した統合版
# v3.2 での変更点：
# - 「作った順」ソートを追加（ページ上のボタンで カテゴリ順／作った順（新しい順）／作った順（古い順）を切替）
#   作った日時は git の初回コミット日時を優先し、無ければファイルの作成日時→更新日時。
#   各項目に作成日も表示する。作った順ではカテゴリ見出しを外して全件を一列に並べる
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
    *dojo*|*ashinoko*|*mayonaka*)            echo "00|道場・ゲーム" ;;
    *nixos*|*linux*|*debian*|*alpine*|*flake*|*kaden*|*prownos*)
                                              echo "01|NixOS・Linux" ;;
    *openwrt*|*ddwrt*)                        echo "02|OpenWrt" ;;
    *network*|*lan*|*wifi*|*mdns*|*wireguard*|*nmap*|*_ap_*|*ssh*|*_nat_*)
                                              echo "03|ネットワーク" ;;
    *chromebook*|*asus*|*nexus*|*tpx1*|*loox*|*keyboard*)
                                              echo "04|デバイス" ;;
    *vim*|*emacs*|*obsidian*|*i3*|*dwm*|*sway*|*tmux*|*zellij*|*tilegata*|*kanata*|*warpd*)
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

# 作成日時（作った順ソート用）：git の初回コミット日時を優先し、
# 無ければファイルの作成日時（birth time）、それも無ければ更新日時。
# 「YYYY-MM-DD<TAB>epoch秒」を返す
created_info() {
  local f="$1" ct="" bt=""
  if git rev-parse --git-dir >/dev/null 2>&1; then
    ct=$(git log --format=%ct --reverse -- "$f" 2>/dev/null | head -n 1 || true)
  fi
  if [[ -z "$ct" ]]; then
    bt=$(stat -c %W -- "$f" 2>/dev/null || echo 0)
    if [[ "${bt:-0}" -gt 0 ]]; then
      ct="$bt"
    else
      ct=$(stat -c %Y -- "$f")
    fi
  fi
  printf '%s\t%s' "$(date -d "@$ct" +%Y-%m-%d)" "$ct"
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
  cinfo=$(created_info "$file")
  cdate="${cinfo%%$'\t'*}"
  cepoch="${cinfo##*$'\t'}"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ord" "$cat_name" "$title" "$file" "$date" "$cdate" "$cepoch" >> "$ROWS"
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
    #q { width: 100%; box-sizing: border-box; padding: .5em; font-size: 1em; margin: 1em 0 .5em; }
    .sortbar { margin: .5em 0 1em; }
    .sortbar button { padding: .35em .8em; margin-right: .4em; font-size: .95em; border: 1px solid #999; border-radius: 4px; background: #f4f4f4; cursor: pointer; }
    .sortbar button.on { background: #333; color: #fff; border-color: #333; }
    a { text-decoration: none; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <h1>メモ一覧</h1>
  <p>全 ${TOTAL} 件（自動生成： $(date +%Y-%m-%d)）</p>
  <input id="q" type="search" placeholder="タイトル・ファイル名で検索">
  <p class="sortbar">並び替え：
    <button type="button" data-sort="cat" class="on">カテゴリ順</button>
    <button type="button" data-sort="new">作った順（新しい順）</button>
    <button type="button" data-sort="old">作った順（古い順）</button>
  </p>
  <section id="flat" style="display:none"><h2>作った順</h2><ul id="flatlist"></ul></section>
EOF

current=""
while IFS=$'\t' read -r _ord cat_name title file date cdate cepoch; do
  if [[ "$cat_name" != "$current" ]]; then
    [[ -n "$current" ]] && echo '</ul></section>' >> "$TMPFILE"
    printf '<section class="cat"><h2>%s（%s）</h2><ul>\n' "$(esc "$cat_name")" "${COUNT[$cat_name]}" >> "$TMPFILE"
    current="$cat_name"
  fi
  printf '<li data-created="%s"><a href="%s">%s</a><small>%s ・ 更新 %s ・ 作成 %s</small></li>\n' \
    "$(esc "$cepoch")" "$(esc "$file")" "$(esc "$title")" "$(esc "$file")" "$(esc "$date")" "$(esc "$cdate")" >> "$TMPFILE"
done < "$ROWS"
[[ -n "$current" ]] && echo '</ul></section>' >> "$TMPFILE"

cat >> "$TMPFILE" << 'EOF'
  <script>
    var mode = 'cat';
    var homes = null; // 各 li の元の置き場所（カテゴリ順に戻すため）
    var flat = document.getElementById('flat');
    var flatlist = document.getElementById('flatlist');

    function applySearch() {
      var q = document.getElementById('q').value.toLowerCase();
      var scope = (mode === 'cat')
        ? document.querySelectorAll('section.cat')
        : [flat];
      document.querySelectorAll('li').forEach(function (li) {
        li.style.display = li.textContent.toLowerCase().includes(q) ? '' : 'none';
      });
      scope.forEach(function (s) {
        var visible = Array.prototype.some.call(s.querySelectorAll('li'), function (li) {
          return li.style.display !== 'none';
        });
        if (mode === 'cat' || s === flat) s.style.display = visible ? '' : 'none';
      });
    }

    function setSort(next) {
      mode = next;
      document.querySelectorAll('.sortbar button').forEach(function (b) {
        b.classList.toggle('on', b.getAttribute('data-sort') === next);
      });
      var cats = document.querySelectorAll('section.cat');
      if (next === 'cat') {
        if (homes) {
          homes.forEach(function (h) { h.parent.insertBefore(h.li, h.next); });
        }
        flat.style.display = 'none';
        cats.forEach(function (s) { s.style.display = ''; });
      } else {
        if (!homes) {
          homes = [];
          document.querySelectorAll('section.cat li').forEach(function (li) {
            homes.push({ li: li, parent: li.parentNode, next: li.nextSibling });
          });
        }
        var items = homes.map(function (h) { return h.li; });
        items.sort(function (a, b) {
          var d = Number(a.getAttribute('data-created')) - Number(b.getAttribute('data-created'));
          return next === 'new' ? -d : d;
        });
        items.forEach(function (li) { flatlist.appendChild(li); });
        cats.forEach(function (s) { s.style.display = 'none'; });
        flat.style.display = '';
        flat.querySelector('h2').textContent = next === 'new' ? '作った順（新しい順）' : '作った順（古い順）';
      }
      applySearch();
    }

    document.querySelectorAll('.sortbar button').forEach(function (b) {
      b.addEventListener('click', function () { setSort(b.getAttribute('data-sort')); });
    });
    document.getElementById('q').addEventListener('input', applySearch);
  </script>
</body>
</html>
EOF

mv "$TMPFILE" "$OUTPUT"
echo "完了。出力結果は $OUTPUT に保存されました（全 ${TOTAL} 件）" >&2
