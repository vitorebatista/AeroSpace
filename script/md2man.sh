#!/bin/bash
# Builds a man page from a docs-md/commands/*.md page: prepends the NAME
# section pandoc needs and unwraps the ```synopsis fence into a literal block.
set -euo pipefail

file="$1"
out_dir="${2:-.man}"
name=$(basename "$file" .md)
purpose=$(sed -n 's/^description: //p' "$file" | head -1)

# docs-md/aerospace.md is the top-level aerospace-edge(1) page, not a subcommand.
if test "$name" = aerospace; then
    page="aerospace-edge"
else
    page="aerospace-edge-${name}"
fi

mkdir -p "$out_dir"

{
    echo "% ${page}(1) | AeroSpace Manual"
    echo
    echo "# NAME"
    echo
    echo "${page} - ${purpose}"
    echo
    # Drop YAML frontmatter and the H1; demote nothing else. Turn the synopsis
    # fence into an indented literal block so groff keeps the line breaks.
    awk 'NR>1 && /^---$/ && !fm {fm=1; next} !fm && NR==1 && /^---$/ {next} !fm {next}
         # drop the H1 and the purpose paragraph under it (already in NAME)
         /^# /{lead=1; next}
         lead && /^$/ {next}
         lead {lead=0; next}
         # H2 -> man section heading, uppercased
         /^## /{sub(/^## /,""); print "# " toupper($0); next}
         /^```synopsis$/{print "```"; next}
         {print}' "$file"
    echo
    echo "# BUGS"
    echo
    echo "Bugs can be reported to <https://github.com/vitorebatista/AeroSpace-edge/issues>"
    echo
    echo "# LICENSE"
    echo
    echo "Copyright (C) 2023 Nikita Bobko. Free use of this software is granted under the terms of the MIT License."
} | pandoc -f markdown -t man -s -o "$out_dir/${page}.1"

echo "wrote $out_dir/${page}.1"
