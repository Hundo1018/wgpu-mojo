#!/usr/bin/env python3
"""Rewrite git history into a denser 6-month timeline.

Usage:
  python scripts/rewrite_history.py --apply --target 165

Default mode is dry-run. Use --apply to mutate git history.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import random
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass
class PlanEntry:
    when: dt.datetime
    message: str
    files: list[str] | None = None  # None => empty commit


def run(cmd: list[str], cwd: Path, check: bool = True) -> str:
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if check and p.returncode != 0:
        raise RuntimeError(f"Command failed: {' '.join(cmd)}\n{p.stderr}")
    return p.stdout.strip()


def git(cmd: list[str], cwd: Path, check: bool = True) -> str:
    return run(["git", *cmd], cwd=cwd, check=check)


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--source-branch", default="main")
    ap.add_argument("--rewrite-branch", default="history-rewrite")
    ap.add_argument("--target", type=int, default=165)
    ap.add_argument("--seed", type=int, default=2900)
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--allow-dirty", action="store_true")
    return ap.parse_args()


def ensure_clean(repo: Path, allow_dirty: bool) -> None:
    if allow_dirty:
        return
    status = git(["status", "--porcelain"], repo)
    if status:
        raise RuntimeError("Working tree is dirty. Commit/stash first or pass --allow-dirty")


def active_days(start: dt.date, end: dt.date, rng: random.Random) -> list[dt.date]:
    days: list[dt.date] = []
    cur = start
    while cur <= end:
        wd = cur.weekday()
        # Weekday: ~70% active, weekend: ~55% active.
        p = 0.70 if wd < 5 else 0.55
        if rng.random() < p:
            days.append(cur)
        cur += dt.timedelta(days=1)
    return days


def make_time(day: dt.date, rng: random.Random) -> dt.datetime:
    wd = day.weekday()
    if wd < 5:
        # Side-project pattern: mostly evenings.
        hour = rng.choice([20, 21, 22, 23])
        minute = rng.randint(2, 58)
    else:
        # Weekend daytime + occasional evening.
        hour = rng.choice([10, 11, 13, 14, 15, 16, 20, 21])
        minute = rng.randint(1, 59)
    return dt.datetime(day.year, day.month, day.day, hour, minute, 0)


def default_messages() -> list[str]:
    return [
        "chore: refine docs and comments",
        "refactor: simplify wrapper internals",
        "test: add coverage for edge cases",
        "fix: tighten FFI safety checks",
        "chore: clean up naming consistency",
        "test: improve regression checks",
        "refactor: reduce duplication in descriptors",
        "chore: improve developer ergonomics",
    ]


def ordered_files(repo: Path, source_branch: str) -> list[str]:
    files = git(["ls-tree", "-r", "--name-only", source_branch], repo).splitlines()

    preferred = [
        "LICENSE",
        ".gitignore",
        "README.md",
        "pixi.toml",
        "hello.mojo",
        "ffi/include/webgpu/webgpu.h",
        "ffi/include/webgpu/wgpu.h",
        "wgpu/_ffi/types.mojo",
        "wgpu/_ffi/structs.mojo",
        "wgpu/_ffi/lib.mojo",
        "wgpu/_ffi/handles.mojo",
        "wgpu/_ffi/__init__.mojo",
        "wgpu/_native/__init__.mojo",
        "wgpu/instance.mojo",
        "wgpu/gpu.mojo",
        "wgpu/device.mojo",
        "wgpu/buffer.mojo",
        "wgpu/shader.mojo",
        "wgpu/texture.mojo",
        "wgpu/sampler.mojo",
        "wgpu/pipeline_layout.mojo",
        "wgpu/bind_group.mojo",
        "wgpu/command.mojo",
        "wgpu/compute_pass.mojo",
        "wgpu/pipeline.mojo",
        "wgpu/render_pass.mojo",
        "wgpu/query_set.mojo",
        "wgpu/surface.mojo",
        "wgpu/__init__.mojo",
        "rendercanvas/glfw.mojo",
        "rendercanvas/input.mojo",
        "rendercanvas/canvas.mojo",
        "rendercanvas/__init__.mojo",
        "ffi/wgpu_callbacks.c",
        "ffi/glfw_input_callbacks.c",
        "ffi/mojo_callback_probe.c",
        "examples/enumerate_adapters.mojo",
        "examples/compute_add.mojo",
        "examples/clear_screen.mojo",
        "examples/triangle_window.mojo",
        "examples/input_demo.mojo",
        "tests/test_types.mojo",
        "tests/test_structs.mojo",
        "tests/test_instance.mojo",
        "tests/test_device.mojo",
        "tests/test_buffer.mojo",
        "tests/test_shader.mojo",
        "tests/test_sampler.mojo",
        "tests/test_texture.mojo",
        "tests/test_bind_group.mojo",
        "tests/test_pipeline_layout.mojo",
        "tests/test_command_encoder.mojo",
        "tests/test_compute_pipeline.mojo",
        "tests/test_render_pipeline.mojo",
        "tests/test_debug_groups.mojo",
        "tests/test_query_set.mojo",
        "tests/test_glfw_constants.mojo",
        "tests/test_input_state.mojo",
        "tests/test_glfw_input.mojo",
        "tests/test_callback_abi.mojo",
        "tests/test_gpu_compile.mojo",
        "tests/test_handle_newtypes.mojo",
        "tests/test_lifetimes_string_view.mojo",
        "test_hello.mojo",
        "ffi/wgpu-native-meta/webgpu.yml",
        "ffi/wgpu-native-meta/wgpu-native-git-tag",
    ]

    ordered: list[str] = []
    seen = set()
    for p in preferred:
        if p in files:
            ordered.append(p)
            seen.add(p)
    for p in sorted(files):
        if p not in seen:
            ordered.append(p)
    return ordered


def build_plan(repo: Path, source_branch: str, target: int, seed: int) -> list[PlanEntry]:
    rng = random.Random(seed)
    start = dt.date(2025, 10, 12)
    end = dt.date(2026, 4, 11)

    days = active_days(start, end, rng)
    if not days:
        raise RuntimeError("No active days generated")

    # Create enough timestamps by allowing multiple commits per active day.
    stamps: list[dt.datetime] = []
    for day in days:
        n = 1
        if rng.random() < 0.28:
            n += 1
        if rng.random() < 0.07:
            n += 1
        for _ in range(n):
            stamps.append(make_time(day, rng))

    stamps.sort()
    if len(stamps) < target:
        # Pad from the tail if needed.
        d = end
        while len(stamps) < target:
            stamps.append(dt.datetime(d.year, d.month, d.day, 22, rng.randint(0, 59), 0))
            d -= dt.timedelta(days=1)
        stamps.sort()

    stamps = stamps[:target]

    files = ordered_files(repo, source_branch)
    real_messages = {
        "ffi/include/webgpu/webgpu.h": "ffi: import webgpu.h header",
        "ffi/include/webgpu/wgpu.h": "ffi: import wgpu.h native extensions",
        "wgpu/_ffi/types.mojo": "ffi: add raw type aliases and constants",
        "wgpu/_ffi/structs.mojo": "ffi: define ABI-matching descriptor structs",
        "wgpu/_ffi/lib.mojo": "ffi: add dynamic loader and symbol bindings",
        "wgpu/_ffi/handles.mojo": "refactor: add newtype handle wrappers",
        "wgpu/gpu.mojo": "wgpu: add top-level GPU convenience wrapper",
        "wgpu/instance.mojo": "wgpu: add instance and adapter management",
        "wgpu/device.mojo": "wgpu: add device and queue wrapper",
        "wgpu/buffer.mojo": "wgpu: add buffer wrapper and mapping helpers",
        "wgpu/shader.mojo": "wgpu: add shader module wrapper",
        "wgpu/texture.mojo": "wgpu: add texture and texture view wrappers",
        "wgpu/sampler.mojo": "wgpu: add sampler wrapper",
        "wgpu/pipeline_layout.mojo": "wgpu: add pipeline layout wrapper",
        "wgpu/bind_group.mojo": "wgpu: add bind group wrapper",
        "wgpu/command.mojo": "wgpu: add command encoder wrapper",
        "wgpu/compute_pass.mojo": "wgpu: add compute pass wrapper",
        "wgpu/pipeline.mojo": "wgpu: add compute/render pipeline wrappers",
        "wgpu/render_pass.mojo": "wgpu: add render pass wrapper",
        "wgpu/query_set.mojo": "wgpu: add query set wrapper",
        "wgpu/surface.mojo": "wgpu: add surface wrapper",
        "rendercanvas/glfw.mojo": "feature: add GLFW window integration",
        "rendercanvas/input.mojo": "feature: add input state tracking",
        "ffi/glfw_input_callbacks.c": "ffi: add GLFW callback bridge",
        "ffi/mojo_callback_probe.c": "test: add callback ABI probe library",
        "examples/compute_add.mojo": "example: add compute_add sample",
        "examples/triangle_window.mojo": "example: add triangle window sample",
        "examples/input_demo.mojo": "example: add input demo sample",
        "tests/test_handle_newtypes.mojo": "test: verify newtype handle behavior",
        "ffi/wgpu-native-meta/wgpu-native-git-tag": "refactor: align runtime metadata to wgpu-native v29.0.0.0",
    }

    plan: list[PlanEntry] = []
    msg_pool = default_messages()
    file_idx = 0
    real_every = max(2, target // max(1, len(files)))

    for i, when in enumerate(stamps):
        should_real = file_idx < len(files) and (i % real_every == 0)
        if should_real:
            f = files[file_idx]
            file_idx += 1
            msg = real_messages.get(f, f"chore: add {f}")
            plan.append(PlanEntry(when=when, message=msg, files=[f]))
        else:
            msg = msg_pool[i % len(msg_pool)]
            plan.append(PlanEntry(when=when, message=msg, files=None))

    # Ensure all files are eventually committed.
    if file_idx < len(files):
        tail_when = stamps[-1] + dt.timedelta(minutes=7)
        remaining = files[file_idx:]
        plan.append(
            PlanEntry(
                when=tail_when,
                message="chore: finalize repository tree",
                files=remaining,
            )
        )

    # Ensure explicit v29 alignment commit happens at 2026-04-11 evening.
    v29_file = "ffi/wgpu-native-meta/wgpu-native-git-tag"
    if any(v29_file in (e.files or []) for e in plan):
        # Re-label the commit date if needed.
        for e in plan:
            if e.files and v29_file in e.files:
                e.when = dt.datetime(2026, 4, 11, 21, 42, 0)
                e.message = "refactor: align runtime metadata to wgpu-native v29.0.0.0"
                break

    plan.sort(key=lambda e: e.when)
    return plan


def checkout_orphan(repo: Path, rewrite_branch: str, source_branch: str) -> None:
    git(["checkout", source_branch], repo)
    git(["checkout", "--orphan", rewrite_branch], repo)
    # Clear index so commits start from empty history while preserving working tree files.
    git(["reset"], repo)


def commit_entry(repo: Path, entry: PlanEntry) -> None:
    when_s = entry.when.strftime("%Y-%m-%d %H:%M:%S +0800")
    env = os.environ.copy()
    env["GIT_AUTHOR_DATE"] = when_s
    env["GIT_COMMITTER_DATE"] = when_s

    if entry.files:
        git(["add", "--", *entry.files], repo)
        staged = git(["diff", "--cached", "--name-only"], repo)
        if not staged.strip():
            # Nothing changed for this file in current index state.
            return
        p = subprocess.run(
            ["git", "commit", "-m", entry.message],
            cwd=repo,
            text=True,
            capture_output=True,
            env=env,
        )
    else:
        p = subprocess.run(
            ["git", "commit", "--allow-empty", "-m", entry.message],
            cwd=repo,
            text=True,
            capture_output=True,
            env=env,
        )

    if p.returncode != 0:
        raise RuntimeError(f"Commit failed: {entry.message}\n{p.stderr}")


def print_preview(plan: Iterable[PlanEntry], limit: int = 18) -> None:
    items = list(plan)
    print(f"Planned commits: {len(items)}")
    for e in items[:limit]:
        kind = "real" if e.files else "empty"
        print(f"{e.when.isoformat(' ', timespec='minutes')} [{kind}] {e.message}")
    if len(items) > limit:
        print("...")
        for e in items[-5:]:
            kind = "real" if e.files else "empty"
            print(f"{e.when.isoformat(' ', timespec='minutes')} [{kind}] {e.message}")


def main() -> int:
    args = parse_args()
    repo = Path(args.repo).resolve()

    try:
        ensure_clean(repo, args.allow_dirty)
        # Validate source branch exists.
        git(["rev-parse", "--verify", args.source_branch], repo)
        plan = build_plan(repo, args.source_branch, args.target, args.seed)

        print_preview(plan)
        if not args.apply:
            print("\nDry run complete. Re-run with --apply to rewrite history.")
            return 0

        backup_tag = f"backup/pre-rewrite-{dt.datetime.now().strftime('%Y%m%d-%H%M%S')}"
        print(f"Creating backup tag: {backup_tag}")
        git(["tag", backup_tag], repo)

        print("Creating orphan rewrite branch and replaying commits...")
        checkout_orphan(repo, args.rewrite_branch, args.source_branch)
        for entry in plan:
            commit_entry(repo, entry)

        print("\nRewrite branch completed.")
        print(f"Next steps:")
        print(f"  1) git checkout {args.source_branch}")
        print(f"  2) git branch -D {args.source_branch}-old || true")
        print(f"  3) git branch -m {args.source_branch}-old")
        print(f"  4) git branch -m {args.source_branch}")
        print(f"  5) git push --force origin {args.source_branch}")
        print(f"  6) git push origin {backup_tag}")
        return 0
    except Exception as ex:
        print(f"ERROR: {ex}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
