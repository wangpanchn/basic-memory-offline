#!/usr/bin/env bash
# Rebuild the win_amd64 offline wheel bundle for basic-memory.
# Run this on a machine with PyPI access; the output zip is what the intranet
# machine consumes. Nothing here runs on the offline side.
#
#   ./scripts/build-bundle.sh            # uses ../build/ as scratch dir
#
# Verified with: basic-memory 0.24.1, uv 0.13.5, pip 26.2.2, CPython 3.12 + 3.13.
set -euo pipefail

VERSION="${VERSION:-0.24.1}"
PLATFORM="${PLATFORM:-win_amd64}"
PYVERS="${PYVERS:-3.12 3.13}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD:-$ROOT/build}"
OUT="$BUILD/dist"
NAME="basic-memory-$VERSION-$PLATFORM"
STAGE="$OUT/$NAME"

mkdir -p "$BUILD" "$STAGE"
cd "$BUILD"

# --- 1. resolve the dependency set for the target platform -------------------
echo "== resolving pins for $PLATFORM ($PYVERS)"
printf 'basic-memory==%s\nsocksio\n' "$VERSION" > req.in
for v in $PYVERS; do
  uv pip compile req.in --python-platform windows --python-version "$v" \
    --no-header --quiet -o "req-$PLATFORM-py$v.txt"
  echo "   py$v: $(grep -c '==' "req-$PLATFORM-py$v.txt") pins"
done

# --- 2. pin pip so cross-platform downloads are reproducible ------------------
if [ ! -x .piptool/bin/python ]; then
  uv venv .piptool --python 3.13
  uv pip install --python .piptool/bin/python pip setuptools wheel
fi
PIPPY=.piptool/bin/python

# --- 3. fetch one wheel per pin, per interpreter -----------------------------
# pip's cross-platform resolver re-evaluates markers against the host, so
# `uvloop ; sys_platform != "win32"` (a basic-memory dependency) aborts the run.
# The pins are already resolved for Windows, so fetch each one with --no-deps
# and verify closure afterwards.
for v in $PYVERS; do
  cp="cp${v/./}"
  rm -rf "wheels-$cp"
  "$PIPPY" - "$PLATFORM" "req-$PLATFORM-py$v.txt" "wheels-$cp" "$v" <<'PY'
import concurrent.futures as cf, subprocess, sys
from pathlib import Path

platform, req, outdir, pyver = sys.argv[1:5]
pins = [l.split("#")[0].strip() for l in Path(req).read_text().splitlines()]
pins = [p for p in pins if "==" in p]
Path(outdir).mkdir(parents=True, exist_ok=True)
target = ["--platform", platform, "--python-version", pyver, "--implementation", "cp",
          "--abi", "cp" + pyver.replace(".", ""), "--abi", "abi3", "--abi", "none"]

def fetch(pin):
    r = subprocess.run([sys.executable, "-m", "pip", "download", "--no-deps",
                        "--only-binary=:all:", *target, "--find-links", "wheels-pure",
                        "-d", outdir, pin], capture_output=True, text=True)
    return pin, r.returncode, r.stderr.strip().splitlines()[-1:] or [""]

fail = []
with cf.ThreadPoolExecutor(max_workers=8) as pool:
    for pin, rc, err in pool.map(fetch, pins):
        if rc:
            fail.append(f"{pin}: {err[0][:120]}")
print(f"{platform}/cp{pyver.replace('.', '')}: {len(pins)} pins, "
      f"{len(list(Path(outdir).glob('*.whl')))} wheels")
for f in fail:
    print("  MISS", f)
sys.exit(1 if fail else 0)
PY
done

# --- 4. packages that ship no wheel at all get built once as py3-none-any ----
mkdir -p wheels-pure
MISSING=$(for v in $PYVERS; do grep -ho '^[a-zA-Z0-9_.-]*==[^ ]*' "req-$PLATFORM-py$v.txt"; done | sort -u \
  | while read -r pin; do
      name="${pin%%==*}"
      ls wheels-*/"${name//-/_}"*.whl wheels-*/"$name"*.whl >/dev/null 2>&1 || echo "$pin"
    done)
if [ -n "$MISSING" ]; then
  echo "== building missing wheels: $MISSING"
  # shellcheck disable=SC2086
  "$PIPPY" -m pip wheel --no-deps $MISSING -w wheels-pure
else
  echo "== every pin has a wheel for the target"
fi

# --- 5. dedupe pure-python wheels into wheels-pure ---------------------------
"$PIPPY" - <<'PY'
import hashlib, shutil
from pathlib import Path
pure = Path("wheels-pure"); pure.mkdir(exist_ok=True)
seen = {}
for d in sorted(Path(".").glob("wheels-cp*")):
    for w in sorted(d.glob("*-none-any.whl")):
        h = hashlib.sha256(w.read_bytes()).hexdigest()
        if h in seen:
            w.unlink()
        else:
            seen[h] = w.name
            shutil.move(str(w), pure / w.name)
print(f"shared pure wheels: {len(seen)}")
PY

# --- 6. stage, checksum, zip -------------------------------------------------
echo "== staging $NAME"
rm -rf "$STAGE"
mkdir -p "$STAGE"
for v in $PYVERS; do cp -r "wheels-cp${v/./}" "$STAGE/"; done
cp -r wheels-pure "$STAGE/"
cp req.in "$STAGE/pins-source.in"
for v in $PYVERS; do cp "req-$PLATFORM-py$v.txt" "$STAGE/"; done
cp -r "$ROOT/skills" "$STAGE/skills"
cp "$ROOT/docs/offline-embedding.md" "$STAGE/OFFLINE-EMBEDDING.md"

( cd "$STAGE" && find . -name '*.whl' -printf '%P\n' | sort | xargs sha256sum > SHA256SUMS.txt )
echo "== staged: $(grep -c . "$STAGE/SHA256SUMS.txt") wheels, $(du -sh "$STAGE" | cut -f1)"

rm -f "$OUT/$NAME.zip"
( cd "$OUT" && zip -qr "$NAME.zip" "$NAME" )
echo "== bundle: $OUT/$NAME.zip ($(du -h "$OUT/$NAME.zip" | cut -f1))"

# --- 7. optional: prove the wheel set is closed for the target --------------
for v in $PYVERS; do
  echo "== closure check py$v (no network)"
  uv pip install --no-index --offline --no-build \
    --find-links "$STAGE/wheels-pure" --find-links "$STAGE/wheels-cp${v/./}" \
    -r "$STAGE/req-$PLATFORM-py$v.txt" \
    --python-platform windows --python-version "$v" \
    --target "$BUILD/.closure-$v" --quiet
  echo "   ok"
  rm -rf "$BUILD/.closure-$v"
done
