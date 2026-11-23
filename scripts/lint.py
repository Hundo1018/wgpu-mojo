"""Fast static checks in one command: `pixi run lint` (no GPU, no build).

    pixi run lint                # every check, one line each; exit 1 if any fails
    pixi run lint -- --only ruff
    pixi run lint -- --list

Each check prints its own findings under its line (ported from ludens-core's scripts/lint.py):

  ruff         scripts/: the bug-finding rules in ruff.toml
  shellcheck   scripts/*.sh and conda.recipe/build.sh

CI runs it in the Test job (.github/workflows/ci.yml) before the native setup.
"""

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def shell_files() -> list[str]:
    files = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "scripts").glob("*.sh"))
    return files + ["conda.recipe/build.sh"]


CHECKS = {
    "ruff": lambda: ["ruff", "check", "--quiet", "--output-format", "concise", "."],
    "shellcheck": lambda: ["shellcheck", "-f", "gcc", *shell_files()],
}


def run(argv: list[str]) -> tuple[bool, str]:
    try:
        p = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return False, f"{argv[0]} not found (run through pixi: `pixi run lint`)"
    return p.returncode == 0, (p.stdout + p.stderr).strip()


def run_check(name: str) -> tuple[bool, str]:
    return run(CHECKS[name]())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="comma-separated subset of: " + ", ".join(CHECKS))
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    if a.list:
        print("\n".join(CHECKS))
        return 0
    names = a.only.split(",") if a.only else list(CHECKS)
    unknown = [n for n in names if n not in CHECKS]
    if unknown:
        print("lint: unknown check(s): " + ", ".join(unknown))
        return 2
    failed = []
    for n in names:
        ok, out = run_check(n)
        print(f"[lint] {'ok  ' if ok else 'FAIL'} {n}")
        if not ok:
            failed.append(n)
            for line in out.splitlines():
                print("    " + line)
    if failed:
        print("lint: failed: " + ", ".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
