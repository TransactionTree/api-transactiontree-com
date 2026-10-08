# api.transactiontree.com

Source of truth for the [TransactionTree API documentation portal](https://api.transactiontree.com).

The published portal at `https://api.transactiontree.com` is rendered by Postman from the collection in this repo. After a change is merged to `main`, a maintainer runs the **publish-to-postman** workflow by hand (Actions → publish-to-postman → Run workflow) to update the live portal. Merging alone does not publish.

## What's documented here

| Folder | API |
|---|---|
| Overview | Platform overview, common conventions |
| Virtual Receipt Gateway (VRG) | Digital receipt delivery API — `/VRG/*` endpoints |
| BranchedOut Retail Marketing Cloud | Legacy marketing platform (predecessor to Digivize) |
| MessageManager | Transactional messaging API |

## Contributing

External integrators and TT staff are both welcome to contribute. See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow. Security issues should go through [private disclosure](SECURITY.md), not public issues.

## How the sync works

```
GitHub PR merged to main
        │
        ▼  (maintainer: Actions → Run workflow; manual, workflow_dispatch only)
.github/workflows/publish-to-postman.yml
        │
        ├─ Validates collection.json parses
        ├─ Runs internal-leak scan
        ├─ Runs gitleaks secret scan
        │
        ▼
PUT https://api.getpostman.com/collections/{id}
        │
        ▼
api.transactiontree.com portal updates within ~1 minute
```

The Postman collection ID this repo syncs to is configured in the workflow file. Edits to the published portal must come through this repo — direct edits in the Postman UI will be overwritten on the next sync.

## Local development

To test changes locally before opening a PR:

1. Edit `postman/collection.json` (or open it in Postman, edit, then export back into the file)
2. Run the pre-publish scan: `scripts/internal-leak-check.sh postman/collection.json`
3. Open a PR — CI runs the same scans plus JSON validation

## License

[Apache License 2.0](LICENSE). The API specification and example payloads in this repo are released openly so integrators can build against them freely.
