# SAST Integration — C / C++ (README)

This repository contains a minimal SAST integration for C projects using:
- `clang-tidy` (configurable checks)
- Clang Static Analyzer (`clang --analyze`)
- `cppcheck`
- SARIF conversion & merging for upload to Code Scanning (GitHub)

---

## What’s included

- `main.c`, `utils.c` — example source files.
- `CMakeLists.txt` — builds the project and exports `compile_commands.json`.
- `run_all_sast.sh` — runs clang-tidy, clang-analyzer and cppcheck and writes outputs to `sast-reports/`.
- `.clang-tidy` — recommended clang-tidy configuration (focused checks).
- `.vscode/tasks.json` — VS Code tasks for Build / clang-tidy / clang-analyze / cppcheck / combined tasks.
- `sast-reports/` — output directory where tools and SARIF converters will write reports.
- `sast-reports/*.py` — small Python converters for cppcheck → SARIF and clang outputs → SARIF.

---

## Quick setup (WSL)

```bash
# inside WSL
sudo apt update
sudo apt install -y build-essential cmake clang clang-tidy cppcheck python3 python3-pip
# (optional) install ninja if you prefer Ninja generator
# open the project in VS Code (Remote - WSL)
```

## Build (generate compile DB)

```bash
# project root
rm -rf build
cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -G "Unix Makefiles"
cmake --build build
ls -l build/compile_commands.json
```

> `compile_commands.json` is essential: clang-tools use it to know compiler flags & include paths for each translation unit.

## Run SAST locally (one command)

```bash
# runs clang-tidy, clang --analyze and cppcheck; writes reports to sast-reports/
./run_all_sast.sh
ls -l sast-reports
```

## VS Code usage

- Open the project in **Remote - WSL** window.
- **Ctrl+Shift+B** runs the default task (clang-tidy focused).
- Terminal → Run Task… to run:
  - `Build (CMake)`  
  - `clang-tidy (focused, default)`  
  - `clang-analyze (main)` / `clang-analyze (utils)`  
  - `cppcheck (file-list)`  
  - `All SAST (build->tidy->cppcheck)`  
  - `Run all SAST (script)`


## Testing vulnerabilities (examples)

Create temporary test files to demonstrate detection (do not commit them):

**Buffer overflow**

```c
// test_bug.c
#include <string.h>
int main(void) {
  char s[4];
  strcpy(s, "this-is-long");
  return 0;
}
```
Run:

```bash
cppcheck --enable=all --inconclusive --std=c11 --template='{file}:{line}:{column}: {severity}: {id}: {message}' test_bug.c
clang-tidy test_bug.c -p build -- -I. 2>&1 | sed -n '1,200p'
```

**Null dereference**

```c
// test_null.c
int main() {
  char *p = 0;
  *p = 1; // analyzer should flag
  return 0;
}
```
Run analyzer:

```bash
clang --analyze test_null.c -I. -Xclang -analyzer-output -Xclang text
```

After testing remove test files:

```bash
rm -f test_bug.c test_null.c
```

---

## SARIF (for dashboards / GitHub Code Scanning)

- SARIF is a standard JSON format for static analysis results. It aggregates findings from multiple tools.
- Use provided scripts to convert outputs into SARIF:
  - `sast-reports/cppcheck_to_sarif.py` (cppcheck XML → SARIF)
  - `sast-reports/clang_tidy_to_sarif.py` (clang-tidy text → SARIF)
  - `sast-reports/clang_analyze_text_to_sarif.py` (clang analyzer text → SARIF)
- Merge SARIF files into `sast-reports/merged.sarif` (merge script included).
- In CI: use `github/codeql-action/upload-sarif@v2` to upload `sast-reports/merged.sarif` to GitHub Code Scanning.

---

## Which report to inspect first

1. `sast-reports/clang-tidy.txt` — primary, actionable findings.
2. `sast-reports/clang-analyze*.txt` — path-sensitive issues.
3. `sast-reports/cppcheck_gcc.txt` or `sast-reports/cppcheck.sarif` — cppcheck results.
4. `sast-reports/merged.sarif` — aggregated SARIF for dashboards.
5. `build/compile_commands.json` — compiler DB (not a findings report, but essential).

---

## CI (GitHub Actions)

A sample workflow (`.github/workflows/sast.yml`) is provided as an example. It:
- builds the project,
- runs clang-tidy, clang-analyze, cppcheck,
- stores textual reports in `sast-reports/` and uploads them as artifacts,
- (optional) uploads merged SARIF to GitHub Code Scanning.

---

## Troubleshooting quick tips

- If clang-tidy prints many system header warnings → use `.clang-tidy` or `-header-filter` to limit diagnostics.
- If cppcheck scans build files → use `--file-list` excluding `build/`.
- If clang-tidy misses include paths → ensure `build/compile_commands.json` exists and run with `-p build`.

---




