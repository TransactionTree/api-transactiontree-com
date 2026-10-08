# api.transactiontree.com

Source of truth for the [TransactionTree API documentation portal](https://api.transactiontree.com).

The portal at `https://api.transactiontree.com` is Postman's published documentation for the Postman collection **`TransactionTree`** (`6363906-32d79127-a4bd-4cf8-8d88-1357be996089`, published doc id `2sBYAq1Dve`). `postman/collection.json` in this repo is that collection. After a change is merged to `main`, a maintainer runs the **publish-to-postman** workflow by hand (Actions → publish-to-postman → Run workflow) to update the live portal. Merging alone does not publish.

> Before 2026-10-08 this repo mirrored an older collection (`6363906-51a49200-…`, now named "TransactionTree - LEGACY" and no longer published) while the live collection was edited directly in Postman. The repo now holds the live collection; edit it here, not in Postman.

## What's documented here

| Folder | API |
|---|---|
| Overview | Platform overview, credentials and security, common conventions |
| Retail Integration Gateway (RIG) | Digital receipt and customer API (formerly VRG) — `/VRG/*` endpoints |
| Customer360 | Customer, orders, loyalty, coupons, gift cards, products, returns, privacy (formerly BORMC) |
| MessageManager | Transactional messaging API |
| Digivize | Campaigns, contacts, SMS/MMS, email, events, PIM, storage, templates, validation, webhooks |

Example hosts are deliberately generic (`rig.sandbox.example.com`, `c360.sandbox.example.com`, `mm.sandbox.example.com`, `digivize.sandbox.example.com`). Integrators receive their real sandbox and production hosts with their credentials.

## Contributing

External integrators and TT staff are both welcome to contribute. See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow. Security issues should go through [private disclosure](SECURITY.md), not public issues.

## How publishing works

```
GitHub PR merged to main
        │
        ▼  maintainer: Actions → publish-to-postman → Run workflow  (manual, workflow_dispatch only)
.github/workflows/publish-to-postman.yml
        │
        ├─ Real publishes run only from main (dry runs work on any branch)
        ├─ Validates collection.json parses
        ├─ Runs the internal-leak scan and gitleaks
        ├─ Reads the live Postman collection and REFUSES TO PUBLISH if it changed in any way since the
        │  last publish (compared with the file at git tag `postman-published`): an edited description,
        │  body, header, script, auth block, variable, or an added/removed folder, request or example.
        │  Before the first publish there is no tag, so it checks structure only: live may not have any
        │  folder, request, saved example or variable that this repo lacks.
        │
        ▼
PUT https://api.getpostman.com/collections/{id}
        │
        ├─ Reads the collection back and confirms Postman now holds exactly this file's content
        ├─ Moves the `postman-published` tag to this commit
        ▼
api.transactiontree.com portal updates within ~1 minute
```

Edits to the published portal must come through this repo. If something was changed directly in Postman, the publish stops and lists what changed instead of overwriting it: export the collection from Postman, put it in `postman/collection.json`, run the leak scan, and open a PR.

Comparisons ignore only Postman's timestamps and record ids (`updatedAt`, `createdAt`, `lastUpdatedBy`, `owner`, `fork`, `uid`). A round trip through Postman returns everything else unchanged.

## Local development

1. Edit `postman/collection.json` (or open it in Postman, edit, then export back into the file).
2. Run the pre-publish scan: `bash scripts/internal-leak-check.sh postman/collection.json` (needs `jq` and GNU `grep -P`).
3. Open a PR. CI runs the same scans plus JSON validation.

`scripts/postman_guard.py drift <live.json> <repo.json> [<last-published.json>]` and `… match <repo.json> <live.json>` are the publish-time checks; they print item paths only, never values.

## License

[Apache License 2.0](LICENSE). The API specification and example payloads in this repo are released openly so integrators can build against them freely.
