#!/usr/bin/env python3
"""Make sure publishing the repo's collection can never drop anything from the live Postman collection.

  postman_guard.py drift  <live.json> <repo.json>   before a publish: fail if the live collection has any
                                                     folder, request or saved example (by Postman id) that the
                                                     repo file does not have, i.e. someone edited Postman directly.
  postman_guard.py match  <repo.json> <live.json>   after a publish: fail unless Postman now has exactly the
                                                     repo's structure (same items, same order, same ids,
                                                     same saved examples, same variables).

Prints names and ids only, never values.
"""
import json
import sys


def load(p):
    d = json.load(open(p, encoding="utf-8"))
    return d.get("collection", d)


def nodes(c):
    """(path, id, kind, example-ids) for every folder and request, in order."""
    out = []

    def walk(items, path=()):
        for it in items:
            p = path + (it.get("name", ""),)
            iid = it.get("id") or it.get("_postman_id") or it.get("uid")
            out.append((" / ".join(p), iid, "folder" if "item" in it else "request",
                        [r.get("id") for r in it.get("response", [])]))
            if "item" in it:
                walk(it["item"], p)

    walk(c.get("item", []))
    return out


def drift(live_p, repo_p):
    live, repo = nodes(load(live_p)), nodes(load(repo_p))
    repo_ids = {i for _, i, _, _ in repo}
    repo_ex = {e for *_, ex in repo for e in ex}
    missing = [(p, k) for p, i, k, _ in live if i not in repo_ids]
    missing_ex = [(p, e) for p, _, _, ex in live for e in ex if e not in repo_ex]
    if missing or missing_ex:
        print("REFUSING TO PUBLISH: the live Postman collection has content this repo does not.")
        print("Someone edited the collection directly in Postman. Mirror those changes into")
        print("postman/collection.json first (export from Postman, run the leak scan, open a PR).")
        for p, k in missing:
            print(f"   live-only {k}: {p}")
        for p, e in missing_ex:
            print(f"   live-only saved example on: {p} ({e})")
        return 1
    print(f"OK: every live folder, request and saved example ({len(live)} items) exists in the repo file.")
    return 0


def match(repo_p, live_p):
    r, l = load(repo_p), load(live_p)
    a, b = nodes(r), nodes(l)
    problems = []
    if [x[:3] for x in a] != [x[:3] for x in b]:
        problems.append("folders/requests differ (names, order or ids)")
    if [x[3] for x in a] != [x[3] for x in b]:
        problems.append("saved examples differ")
    if [v.get("key") for v in r.get("variable", [])] != [v.get("key") for v in l.get("variable", [])]:
        problems.append("variables differ")
    if problems:
        print("MISMATCH after publish: " + "; ".join(problems))
        ra, la = {x[1]: x[0] for x in a}, {x[1]: x[0] for x in b}
        for i in sorted(set(ra) - set(la), key=str):
            print("   in repo, not in Postman:", ra[i])
        for i in sorted(set(la) - set(ra), key=str):
            print("   in Postman, not in repo:", la[i])
        return 1
    reqs = sum(1 for x in a if x[2] == "request")
    print(f"OK: Postman matches the repo ({reqs} requests, {len(a) - reqs} folders, {sum(len(x[3]) for x in a)} saved examples).")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in ("drift", "match"):
        print(__doc__)
        sys.exit(2)
    sys.exit(drift(sys.argv[2], sys.argv[3]) if sys.argv[1] == "drift" else match(sys.argv[2], sys.argv[3]))
