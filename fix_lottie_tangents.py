"""Repair .lottie bundles damaged by the lottietools.online converter.

The converter rewrites bezier tangents (i/o) from vertex-relative offsets
(spec-compliant) into absolute coordinates, injects non-standard fields
(__complete / completed / _render) and duplicates precomp layers inline.
This script reverses those mutations in place; bundles without the
converter fingerprint are left untouched.

Usage: py -I fix_lottie_tangents.py <file.lottie> [more.lottie ...]
A .bak copy of each modified bundle is written next to the original.
"""
import json
import os
import shutil
import sys
import zipfile

FINGERPRINT_KEYS = ("__complete", "_render")


def has_fingerprint(doc):
    """Detect converter output by its injected non-standard markers."""
    stack = [doc]
    while stack:
        o = stack.pop()
        if isinstance(o, dict):
            if any(k in o for k in FINGERPRINT_KEYS):
                return True
            stack.extend(o.values())
        elif isinstance(o, list):
            stack.extend(o)
    return False


def repair(doc):
    """Reverse the converter mutations. Returns repair statistics."""
    stats = {"tangents": 0, "fields": 0, "layers": 0}

    def wp(o):
        if isinstance(o, dict):
            for k in FINGERPRINT_KEYS + ("completed",):
                if k in o:
                    del o[k]
                    stats["fields"] += 1
            # Layer objects never own a 'layers' array (converter duplication)
            if "ty" in o and "layers" in o:
                del o["layers"]
                stats["layers"] += 1
            if {"i", "o", "v"} <= o.keys():
                v, ins, outs = o["v"], o["i"], o["o"]
                if (v and isinstance(v[0], list) and ins and isinstance(ins[0], list)
                        and len(ins) == len(v) == len(outs)):
                    for j in range(len(v)):
                        nums = v[j] + ins[j] + outs[j]
                        if len(v[j]) == len(ins[j]) == len(outs[j]) == 2 and all(
                                isinstance(c, (int, float)) and not isinstance(c, bool) for c in nums):
                            o["i"][j] = [ins[j][d] - v[j][d] for d in range(2)]
                            o["o"][j] = [outs[j][d] - v[j][d] for d in range(2)]
                            stats["tangents"] += 2
            for val in list(o.values()):
                wp(val)
        elif isinstance(o, list):
            for x in o:
                wp(x)

    wp(doc)
    return stats


def diff_count(a, b):
    """Count structural/value mismatches between two parsed JSON trees."""
    if isinstance(a, dict) and isinstance(b, dict):
        n = sum(1 for k in set(a) | set(b) if k not in a or k not in b)
        return n + sum(diff_count(a[k], b[k]) for k in set(a) & set(b))
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return 1
        return sum(diff_count(x, y) for x, y in zip(a, b))
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return 0 if a == b else 1
    return 0 if a == b else 1


def process(path):
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        data = {n: z.read(n) for n in names}

    total = {"tangents": 0, "fields": 0, "layers": 0}
    changed = False
    for n in names:
        if not n.endswith(".json") or n.endswith("manifest.json"):
            continue
        doc = json.loads(data[n].decode("utf-8"))
        if not has_fingerprint(doc):
            continue
        stats = repair(doc)
        data[n] = json.dumps(doc, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        changed = True
        for k in total:
            total[k] += stats[k]

        # Validate against the sibling source .json when available
        sibling = os.path.splitext(path)[0] + ".json"
        if os.path.isfile(sibling):
            with open(sibling, encoding="utf-8") as f:
                src = json.load(f)
            print(f"  {n}: vs source json -> {diff_count(src, doc)} mismatches")

    if not changed:
        print(f"{path}: no converter fingerprint, untouched")
        return

    shutil.copy2(path, path + ".bak")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n in names:  # original entry order preserved
            z.writestr(n, data[n])
    print(f"{path}: repaired tangents={total['tangents']} "
          f"fields={total['fields']} layers_dup={total['layers']} (backup: .bak)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for p in sys.argv[1:]:
        process(p)
