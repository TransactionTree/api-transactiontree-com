# Contributing to api.transactiontree.com

Thanks for considering a contribution. This repo is the source of truth for the public TransactionTree API documentation portal; everything merged here gets published live within a minute or two.

## Who can contribute

- **TransactionTree staff** — open PRs against this repo as part of normal API work.
- **External integrators / customers** — issues and PRs are welcome. We may not merge every PR (some changes need to align with internal roadmap), but we'll respond.

## Workflow

1. Fork (external) or branch (internal) from `main`.
2. Edit `postman/collection.json` directly, or open it in Postman, edit, and export back into the file.
3. Run the pre-publish scan locally: `scripts/internal-leak-check.sh postman/collection.json`
4. Open a PR.
5. CI runs JSON validation, the leak scan, and gitleaks. All must pass.
6. CODEOWNERS review required before merge.
7. On merge to `main`, the publish workflow auto-syncs the collection to Postman.

## What belongs here

✅ Public API endpoints, example requests/responses, schemas, descriptions, conventions.

❌ **Do not commit**:
- Real API keys, sectokens, or passwords (use placeholders like `<your-api-key>`)
- Internal IP addresses (`10.x.x.x`, `192.168.x.x`)
- Internal hostnames (`*.bormc.com` admin paths, `*.lynxs.local`, `*.lynxs.cloud`)
- Customer-specific endpoint paths that reveal which customer uses what
- PII in example payloads — use obviously-synthetic data (`Jane Test`, `test@example.com`)

The CI scanners catch many of these, but they are not exhaustive. When in doubt, ask in the PR.

## Reporting issues

- **API bugs / docs improvements**: open a regular issue.
- **Security vulnerabilities**: do NOT open a public issue. See [SECURITY.md](SECURITY.md) for the private disclosure channel.

## Style

- Endpoint descriptions: one-sentence summary, then a paragraph of detail if needed
- Example payloads: minimal but realistic — show what fields are required vs optional
- Response examples: include common success and at least one error case
