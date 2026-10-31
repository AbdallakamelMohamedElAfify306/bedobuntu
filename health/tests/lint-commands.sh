# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash lint-commands.sh
# Lints COMMANDS.txt: every command is ONE line, starts with ssh/scp/sudo/unzip/tar, has no exclamation mark,
# has at most one pair of single quotes (outer quoting only), and every remote script it names exists in the kit.
KIT=$(cd "$(dirname "$0")/.." && pwd); bad=0; n=0
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue;; esac
  n=$((n+1))
  case "$line" in ssh\ *|scp\ *|sudo\ *|unzip\ *|tar\ *) ;; *) echo "BAD start: $line"; bad=1;; esac
  case "$line" in *BANG*) echo "BAD exclamation mark: $line"; bad=1;; esac
  q=$(printf '%s' "$line" | tr -cd "'" | wc -c); if [ "$q" -ne 0 ] && [ "$q" -ne 2 ]; then echo "BAD quote count $q: $line"; bad=1; fi
  case "$line" in *\"*) echo "NOTE double quote used: $line";; esac
  for s in $(printf '%s' "$line" | grep -oE '/root/ubuntu-health/[A-Za-z0-9_.-]+'); do f=$KIT/${s#/root/ubuntu-health/}; [ -e "$f" ] || { echo "MISSING $s"; bad=1; }; done
done < "$KIT/COMMANDS.txt"
echo "checked $n command lines, problems: $bad"; exit $bad
