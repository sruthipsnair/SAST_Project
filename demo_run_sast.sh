#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
REPORT_DIR="$ROOT/sast-reports"
BUILD_DIR="$ROOT/build"

mkdir -p "$REPORT_DIR"

echo "1) Clean & build (generate compile_commands.json)..."
rm -rf "$BUILD_DIR"
cmake -S . -B "$BUILD_DIR" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -G "Unix Makefiles"
cmake --build "$BUILD_DIR"

# helper: extract list of files from compile_commands.json using python
echo "2) Gathering translation units from compile_commands.json..."
TU_FILES=$(python3 - <<'PY'
import json,sys
db='build/compile_commands.json'
try:
    j=json.load(open(db))
    files=[entry.get('file') for entry in j if 'file' in entry]
    print(' '.join(files))
except Exception as e:
    print('', end='')
PY
)

if [ -z "$TU_FILES" ]; then
  echo "Warning: no translation units found in build/compile_commands.json — defaulting to main.c utils.c"
  TU_FILES="main.c utils.c"
fi
echo "TUs: $TU_FILES"

# run clang-tidy
echo "3) Running clang-tidy on TUs..."
clang-tidy $TU_FILES -p "$BUILD_DIR" 2>&1 | tee "$REPORT_DIR/clang-tidy.raw.txt" || true

# run clang --analyze per TU (text output)
echo "4) Running clang --analyze per TU..."
# Clear previous analyzer files
: > "$REPORT_DIR/clang-analyze-combined.txt"
for tu in $TU_FILES; do
  echo "=== ANALYZE: $tu ===" >> "$REPORT_DIR/clang-analyze-combined.txt"
  clang --analyze "$tu" -I. -Xclang -analyzer-output -Xclang text 2>&1 >> "$REPORT_DIR/clang-analyze-combined.txt" || true
done
# Also split main/utils if desired
cp "$REPORT_DIR/clang-analyze-combined.txt" "$REPORT_DIR/clang-analyze.txt" || true

# run cppcheck -> XML
echo "5) Running cppcheck to produce XML..."
find . -type f \( -name '*.c' -o -name '*.h' -o -name '*.cpp' -o -name '*.hpp' \) -not -path './build/*' > "$REPORT_DIR/files-to-check.txt"
cppcheck --enable=all --inconclusive --std=c11 -I . --suppress=missingIncludeSystem --file-list="$REPORT_DIR/files-to-check.txt" --xml-version=2 --output-file="$REPORT_DIR/cppcheck.xml" 2> /dev/null || true

# convert cppcheck XML -> SARIF using converter if present
if [ -f "$REPORT_DIR/cppcheck_to_sarif.py" ]; then
  echo "6) Converting cppcheck XML -> SARIF..."
  python3 "$REPORT_DIR/cppcheck_to_sarif.py" "$REPORT_DIR/cppcheck.xml" "$REPORT_DIR/cppcheck.sarif" || true
else
  echo "6) cppcheck converter not found at $REPORT_DIR/cppcheck_to_sarif.py — cppcheck.sarif not produced"
fi

# convert clang-tidy raw -> SARIF if converter exists
if [ -f "$REPORT_DIR/clang_tidy_to_sarif.py" ]; then
  echo "7) Converting clang-tidy raw -> SARIF..."
  python3 "$REPORT_DIR/clang_tidy_to_sarif.py" "$REPORT_DIR/clang-tidy.raw.txt" "$REPORT_DIR/clang-tidy.sarif" || true
else
  echo "7) clang-tidy->SARIF converter not found at $REPORT_DIR/clang_tidy_to_sarif.py"
fi

# convert clang-analyze text -> SARIF if converter exists
if [ -f "$REPORT_DIR/clang_analyze_text_to_sarif.py" ]; then
  echo "8) Converting clang-analyze -> SARIF..."
  python3 "$REPORT_DIR/clang_analyze_text_to_sarif.py" "$REPORT_DIR/clang-analyze.txt" "$REPORT_DIR/clang-analyze.sarif" || true
else
  echo "8) clang-analyze->SARIF converter not found at $REPORT_DIR/clang_analyze_text_to_sarif.py"
fi

# merge SARIF files (if present)
echo "9) Merging SARIF files (if any)..."
python3 - <<'PY'
import json,os
out='sast-reports/merged.sarif'
runs=[]
for f in ['sast-reports/cppcheck.sarif','sast-reports/clang-tidy.sarif','sast-reports/clang-analyze.sarif']:
    if os.path.exists(f):
        try:
            j=json.load(open(f))
            runs.extend(j.get('runs',[]))
        except Exception as e:
            print('skip',f,e)
if runs:
    json.dump({'version':'2.1.0','runs':runs},open(out,'w'),indent=2)
    print('merged ->',out)
else:
    print('no sarif files to merge')
PY

# summary: count results in merged SARIF (or individual SARIFs)
echo "10) Summary of findings:"
python3 - <<'PY'
import json,os
def count_results(path):
    if not os.path.exists(path): return 0
    j=json.load(open(path))
    total=0
    for run in j.get('runs',[]):
        total += len(run.get('results',[]))
    return total

files=['sast-reports/cppcheck.sarif','sast-reports/clang-tidy.sarif','sast-reports/clang-analyze.sarif','sast-reports/merged.sarif']
for f in files:
    print(f, "->", count_results(f))
PY

echo ""
echo "Done. Reports are in $REPORT_DIR ."
ls -l "$REPORT_DIR"
echo "Tip: open the SARIF files in VS Code (SARIF viewer) or upload merged.sarif to GitHub Code Scanning."
