#!/usr/bin/env python3
"""Compare melange JS emission between two dune binaries.

Generates a project with a chain of LIBS melange libraries of MODS modules
each and EMITS melange.emit stanzas that all depend on the last library, then
measures for each dune binary:

- cold: build @mel from an empty _build
- noop: build @mel again
- edit: change one module of the first library, build @mel

Each measurement reports wall time, CPU time of dune and all its children,
the number of melc processes (from `dune trace cat`) and the number of files
under _build/default.

usage: shared_emission.py --dune NAME=PATH [--dune NAME=PATH ...] [--emits 1,2,4,8]
                [--libs 20] [--mods 25] [--reps 3] [--jobs N] [--work DIR]

melc and node must be on PATH. The cache is disabled for every build.
"""

import argparse
import json
import os
import resource
import shutil
import statistics
import subprocess
import sys
import tempfile
import time


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def module_source(lib, mod):
    dep = f"L{lib - 1}.M{mod}.v" if lib > 0 else str(mod)
    return f"""let v = {dep} + {mod}

type t = {{ id : int; name : string; tags : string list }}

let make id = {{ id; name = Printf.sprintf "m{lib}_{mod}_%d" id; tags = [] }}

let tag t s = {{ t with tags = s :: t.tags }}

let describe t =
  Printf.sprintf "%s(%d)[%s]" t.name t.id (String.concat "," t.tags)

let all n = List.init n (fun i -> tag (make (i + v)) "x")

let total n = List.fold_left (fun acc t -> acc + t.id) 0 (all n)
"""


def generate(root, libs, mods, emits):
    shutil.rmtree(root, ignore_errors=True)
    write(f"{root}/dune-project", "(lang dune 3.8)\n(using melange 0.1)\n")
    for lib in range(libs):
        deps = f" (libraries l{lib - 1})" if lib > 0 else ""
        write(f"{root}/l{lib}/dune", f"(library (name l{lib}) (modes melange){deps})\n")
        for mod in range(mods):
            write(f"{root}/l{lib}/m{mod}.ml", module_source(lib, mod))
    for e in range(emits):
        write(
            f"{root}/app{e}/dune",
            f"(melange.emit (target out) (alias mel) (libraries l{libs - 1}))\n",
        )
        write(
            f"{root}/app{e}/main.ml",
            f"let () = Js.log (L{libs - 1}.M0.describe (L{libs - 1}.M0.make {e}))\n",
        )


def children_cpu():
    r = resource.getrusage(resource.RUSAGE_CHILDREN)
    return r.ru_utime + r.ru_stime


def melc_count(dune, root):
    out = subprocess.run(
        [dune, "trace", "cat", "--trace-file", os.path.join(root, "_build", "trace.csexp")],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    n = 0
    for line in out.splitlines():
        e = json.loads(line)
        if e.get("cat") == "process" and e.get("name") == "finish":
            if os.path.basename(e["args"].get("prog", "")) == "melc":
                n += 1
    return n


def count_files(root):
    n = 0
    for _, _, files in os.walk(os.path.join(root, "_build", "default")):
        n += len(files)
    return n


def build(dune, root, jobs):
    cmd = [dune, "build", "@mel", "--root", root, "--cache=disabled"]
    if jobs:
        cmd += ["-j", str(jobs)]
    cpu0, t0 = children_cpu(), time.monotonic()
    subprocess.run(cmd, check=True, env={**os.environ, "DUNE_CACHE": "disabled"})
    wall, cpu = time.monotonic() - t0, children_cpu() - cpu0
    return {
        "wall_s": wall,
        "cpu_s": cpu,
        "melc": melc_count(dune, root),
        "files": count_files(root),
    }


def run_once(dune, root, args, emits, check_output):
    generate(root, args.libs, args.mods, emits)
    res = {"cold": build(dune, root, args.jobs)}
    if check_output:
        out = subprocess.run(
            ["node", f"{root}/_build/default/app0/out/app0/main.js"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        res["output"] = out.strip()
    res["noop"] = build(dune, root, args.jobs)
    with open(f"{root}/l0/m0.ml", "a") as f:
        f.write("\nlet edited = 1\n")
    res["edit"] = build(dune, root, args.jobs)
    return res


def median_runs(runs):
    out = {}
    for phase in ("cold", "noop", "edit"):
        out[phase] = {
            k: statistics.median(r[phase][k] for r in runs)
            for k in ("wall_s", "cpu_s", "melc", "files")
        }
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dune", action="append", required=True, help="NAME=PATH")
    p.add_argument("--emits", default="1,2,4,8")
    p.add_argument("--libs", type=int, default=20)
    p.add_argument("--mods", type=int, default=25)
    p.add_argument("--reps", type=int, default=3)
    p.add_argument("--jobs", type=int, default=0)
    p.add_argument("--work", default=None)
    args = p.parse_args()
    dunes = [d.split("=", 1) for d in args.dune]
    work = args.work or tempfile.mkdtemp(prefix="melange-bench-")
    results = []
    for emits in [int(e) for e in args.emits.split(",")]:
        for rep in range(args.reps):
            # Alternate the order of the binaries between repetitions.
            order = dunes if rep % 2 == 0 else list(reversed(dunes))
            for name, dune in order:
                root = os.path.join(work, f"{name}-e{emits}")
                r = run_once(dune, root, args, emits, check_output=True)
                results.append({"dune": name, "emits": emits, "rep": rep, **r})
                print(json.dumps(results[-1]), file=sys.stderr, flush=True)
    summary = []
    for emits in sorted({r["emits"] for r in results}):
        for name, _ in dunes:
            runs = [r for r in results if r["emits"] == emits and r["dune"] == name]
            outputs = {r["output"] for r in runs}
            summary.append(
                {"dune": name, "emits": emits, "outputs": sorted(outputs), **median_runs(runs)}
            )
    print(json.dumps({"libs": args.libs, "mods": args.mods, "reps": args.reps,
                      "jobs": args.jobs, "summary": summary, "runs": results}, indent=1))


if __name__ == "__main__":
    main()
