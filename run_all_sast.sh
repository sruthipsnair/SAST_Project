#!/usr/bin/env bash
set -e
mkdir -p sast-reports

echo "Running clang-tidy (analyzer only, project headers)..."
clang-tidy main.c -p build -checks='clang-analyzer-*' -header-filter='^/root/projects/my_sast_project/.*' -- -I. 2>&1 | tee sast-reports/clang-tidy.txt || true

echo "Running clang --analyze (text output)..."
clang --analyze main.c -I. -Xclang -analyzer-output -Xclang text 2>&1 | tee sast-reports/clang-analyze.txt || true

echo "Running cppcheck on source files..."
find . -type f \( -name '*.c' -o -name '*.h' -o -name '*.cpp' -o -name '*.hpp' \) -not -path './build/*' > files-to-check.txt
cppcheck --enable=all --inconclusive --std=c11 -I . --suppress=missingIncludeSystem --file-list=files-to-check.txt \
  --template='{file}:{line}:{column}: {severity}: {id}: {message}' 2> sast-reports/cppcheck_gcc.txt || true

echo "Reports saved in ./sast-reports/"
