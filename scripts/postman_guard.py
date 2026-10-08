#!/usr/bin/env python3
"""Make sure publishing the repo's collection can never overwrite or drop anything in the live Postman collection.

  postman_guard.py drift <live.json> <repo.json> [<baseline.json>]
      Before a publish.
      With <baseline.json> (the collection as it was last published, from the `postman-published` git tag):
        fail if the live collection differs AT ALL from what was last published — any folder, request,
        example, description, body, header, script, auth block, variable, anything. That means someone
        edited Postman directly, and publishing would overwrite their edit.
      Without a baseline (first publish): fall back to a structural check — fail if live has any folder,
        request, saved example or variable that the repo file lacks.

  postman_guard.py match <repo.json> <live.json>
      After a publish: fail unless Postman now holds exactly the repo file's content.

Postman returns exactly what was uploaded apart from ids-of-record and timestamps (verified 2026-10-08 by a
round trip through a scratch collection), so content is compared after dropping only those volatile fields.
Prints item paths and key paths only, never values.
"""
import hashlib
import json
import sys

VOLATILE = {"updatedAt", "createdAt", "lastUpdatedBy", "owner", "fork", "uid", "_collection_link", "_exporter_id"}


def load(p):
    d = json.load(open(p, encoding="utf-8"))
    return d.get("collection", d)


def norm(o):
    if isinstance(o, dict):
        return {k: norm(v) for k, v in sorted(o.items()) if k not in VOLATILE}
    if isinstance(o, list):
        return [norm(v) for v in o]
    return o


def fingerprint(c):
    return hashlib.sha256(json.dumps(norm(c), sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()


def items(c):
    """{key: (path, normalised item without children)} for every folder and request. Key = Postman id, else path."""
    out = {}

    def walk(nodes, path=()):
        for it in nodes:
            p = path + (it.get("name", ""),)
            key = it.get("id") or it.get("_postman_id") or "path:" + " / ".join(p)
            out[key] = (" / ".join(p), json.dumps(norm({k: v for k, v in it.items() if k != "item"}), sort_keys=True),
                        "folder" if "item" in it else "request", [r.get("id") for r in it.get("response", [])])
            if "item" in it:
                walk(it["item"], p)

    walk(c.get("item", []))
    return out


def top_level(c):
    return {k: json.dumps(norm(v), sort_keys=True) for k, v in c.items() if k != "item"}


def describe_differences(a, b, label_a, label_b):
    ia, ib = items(a), items(b)
    lines = []
    for k in ia.keys() - ib.keys():
        lines.append(f"   only in {label_a}: {ia[k][2]} {ia[k][0]}")
    for k in ib.keys() - ia.keys():
        lines.append(f"   only in {label_b}: {ib[k][2]} {ib[k][0]}")
    for k in ia.keys() & ib.keys():
        if ia[k][1] != ib[k][1]:
            lines.append(f"   content differs: {ib[k][0]}")
    order_a = [k for k in ia]
    order_b = [k for k in ib]
    if [k for k in order_a if k in ib] != [k for k in order_b if k in ia]:
        lines.append("   order of folders/requests differs")
    ta, tb = top_level(a), top_level(b)
    for k in sorted(ta.keys() | tb.keys()):
        if ta.get(k) != tb.get(k):
            lines.append(f"   collection-level '{k}' differs")
    return lines


def drift(live_p, repo_p, baseline_p=None):
    live, repo = load(live_p), load(repo_p)
    if baseline_p:
        base = load(baseline_p)
        if fingerprint(live) == fingerprint(base):
            print(f"OK: the live collection is exactly what was last published (fingerprint {fingerprint(live)[:12]}).")
            return 0
        print("REFUSING TO PUBLISH: the live Postman collection was changed since the last publish.")
        print("Someone edited it directly in Postman; publishing would overwrite those edits. Mirror them into")
        print("postman/collection.json first (export from Postman, run the leak scan, open a PR), then publish.")
        print("\n".join(describe_differences(base, live, "last-published", "live")[:200]))
        return 1
    print("NOTE: no `postman-published` baseline yet (first publish) — structural check only.")
    li, ri = items(live), items(repo)
    missing = [li[k] for k in li.keys() - ri.keys()]
    rex = {e for v in ri.values() for e in v[3]}
    missing_ex = [(v[0], e) for v in li.values() for e in v[3] if e not in rex]
    lv = {v.get("key") for v in live.get("variable", [])}
    rv = {v.get("key") for v in repo.get("variable", [])}
    if missing or missing_ex or (lv - rv):
        print("REFUSING TO PUBLISH: the live Postman collection has content this repo does not.")
        for p, _, kind, _ in missing:
            print(f"   live-only {kind}: {p}")
        for p, e in missing_ex:
            print(f"   live-only saved example on: {p} ({e})")
        for k in sorted(lv - rv, key=str):
            print(f"   live-only variable: {k}")
        return 1
    print(f"OK: every live folder, request, saved example and variable ({len(li)} items) exists in the repo file.")
    return 0


def match(repo_p, live_p):
    repo, live = load(repo_p), load(live_p)
    if fingerprint(repo) == fingerprint(live):
        n = items(repo)
        reqs = sum(1 for v in n.values() if v[2] == "request")
        print(f"OK: Postman now holds exactly the repo file ({reqs} requests, {len(n) - reqs} folders, "
              f"{sum(len(v[3]) for v in n.values())} saved examples; fingerprint {fingerprint(repo)[:12]}).")
        return 0
    print("MISMATCH after publish: Postman's content differs from the repo file.")
    print("\n".join(describe_differences(repo, live, "repo", "Postman")[:200]))
    return 1


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["drift"] and len(a) in (3, 4):
        sys.exit(drift(*a[1:]))
    if a[:1] == ["match"] and len(a) == 3:
        sys.exit(match(*a[1:]))
    if a[:1] == ["fingerprint"] and len(a) == 2:
        print(fingerprint(load(a[1])))
        sys.exit(0)
    print(__doc__)
    sys.exit(2)
