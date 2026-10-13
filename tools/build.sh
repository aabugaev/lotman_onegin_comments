#!/usr/bin/env bash
# Rebuilds the data files. Run from Git Bash in the repository root:
#
#   bash tools/build.sh
#
# Needs pdftotext, perl and curl (all three come with Git for Windows).
#
#   data/onegin.json             text of the novel, from the PDF in the repository root
#   data/lotman-map.json         correspondence: commented fragment -> entry of the commentary
#   local/lotman-comments.json   text of the commentary, for personal use (not committed)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build data local

pdf=$(ls *.pdf 2>/dev/null | head -n 1 || true)
if [ -n "$pdf" ]; then
  pdftotext -enc UTF-8 -simple "$pdf" build/onegin_simple.txt
  perl tools/extract_onegin.pl build/onegin_simple.txt > data/onegin.json
else
  echo "No PDF in the repository root: keeping the existing data/onegin.json" >&2
fi

if [ ! -s build/lotman.html ]; then
  curl -sS -L -o build/lotman.html 'https://feb-web.ru/feb/pushkin/critics/lot/lot-472-.htm?cmd=p'
fi
perl tools/build_lotman.pl build/lotman.html data/onegin.json
