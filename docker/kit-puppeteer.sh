#!/usr/bin/env bash
# kit-puppeteer.sh <path to the kit's scripts/_install-graphics-export.sh>
#
# Prints the Puppeteer version that kit will install at first boot, or nothing
# if the script's selection block is not recognisable.
#
# Why this exists: run.sh calls `dssadmin install-graphics-export` on first boot,
# and that script picks a Puppeteer version from the Node.js version in the image
# (a table that differs between kits). If the image already carries that exact
# version the step is quick; if not, npm re-downloads Puppeteer and its Chromium
# under emulation, which measured ~11 minutes on 12.5.2 (an era-wide pin of 13.7.0
# does not match a kit that selects 21.3.6). So the build asks the kit itself,
# by evaluating its own selection block against this image's Node.
#
# The block runs in a subshell and is bounded by its first and last lines, so
# nothing else in the script — no npm, no cd — is executed.

script="${1:-}"
[ -f "$script" ] || exit 0

block=$(sed -n '/^node_version=\$(node -v)/,/^echo "+ Installing Puppeteer/p' "$script")
[ -n "$block" ] || exit 0

# Drop the closing `echo "+ Installing Puppeteer ..."` line, keep the logic.
logic=$(printf '%s\n' "$block" | sed '$d')
[ -n "$logic" ] || exit 0

# `exit 1` inside the block (unsupported Node) ends only the subshell.
out=$(bash -c "$logic
printf '%s' \"\${puppeteer_version:-}\"" 2>/dev/null | tail -n 1) || exit 0

case "$out" in
    [0-9]*.[0-9]*.[0-9]*) printf '%s' "$out" ;;
esac
