#!/bin/bash
cd "$(dirname "$0")/.."
set -euo pipefail

# Site -> .site (Material for MkDocs), man pages -> .man (pandoc).
# Both are built from docs-md/; there is no asciidoctor step any more.

venv=.deps/docs-venv
if ! test -d "$venv"; then
    python3 -m venv "$venv"
fi
"$venv/bin/pip" install -q -r docs-md/requirements.txt

rm -rf .site .man

"$venv/bin/mkdocs" build --strict -d .site

git rev-parse HEAD > .site/version.html
if ! test -z "$(git status --porcelain)"; then
    echo "git working directory is dirty" >> .site/version.html
fi

for file in docs-md/aerospace-edge.md docs-md/commands/*.md; do
    ./script/md2man.sh "$file" .man > /dev/null
done
echo "built .site and $(ls .man | wc -l | tr -d ' ') man pages"
