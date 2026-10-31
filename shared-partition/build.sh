# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash build.sh
# build.sh: embeds sp_engine.py into shared-part-create.sh
set -e; cd "$(dirname "$0")"
python3 - <<'PY'
t = open("shared-part-create.template.sh").read(); e = open("sp_engine.py").read()
assert "@@ENGINE@@" in t and "\nPYEOF" not in e
open("shared-part-create.sh", "w").write(t.replace("@@ENGINE@@", e.rstrip("\n")))
PY
chmod 755 shared-part-create.sh; bash -n shared-part-create.sh && echo built
