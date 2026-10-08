# Contributing to api.transactiontree.com

Thanks for considering a contribution. This repo is the source of truth for the public TransactionTree API documentation portal; a maintainer publishes merged changes to the live portal by running the publish workflow.

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
7. After merge to `main`, a maintainer runs the `publish-to-postman` workflow (manual `workflow_dispatch`) to sync the collection to Postman. Merging alone does not publish.

**Do not edit the collection directly in Postman.** The repo is the source. If the live collection changed in any way since the last publish, the publish workflow refuses to run and lists what changed, rather than overwrite it. To recover, export the collection from Postman into `postman/collection.json`, run the leak scan, and open a PR.

## What belongs here

✅ Public API endpoints, example requests/responses, schemas, descriptions, conventions.

❌ **Do not commit**:
- Real API keys, sectokens, tenant keys, or passwords. Use the collection variables (`{{sectoken}}`, `{{password}}`, `{{accessTokenKey}}`, `{{X-tenant-Key}}`) or a whole placeholder like `<string>`
- Internal IP addresses (`10.x.x.x`, `172.16–31.x.x`, `192.168.x.x`, `100.64–127.x.x`)
- TT environment hosts (`*.receiptx.com`, `*.bormc.com`, `*.vrgs.io`, `*.cust360.ai`, `*.digivize.ai`, `*.ltschat.com`, `*.lynxs.*`). Use the variables `{{RIGbaseURL}}`, `{{C360URL}}`, `{{MMURL}}`, `{{DigivizeBaseURL}}`, or the example hosts `rig.` / `c360.` / `mm.` / `digivize.sandbox.example.com`
- Customer names, brands, store details, product text or endpoint paths that reveal which customer uses what (use `Example Retailer`, `example-retailer.com`)
- PII in example payloads or recorded responses. The CI scanner accepts only these synthetic values:
  - names: `Test` / `Customer` / `Test Customer` / `Associate, Sample`, or `Nobody` / `Unknown` for a "not found" example (or a placeholder)
  - emails: `@example.com` addresses, plus the documented email-validation fixtures
  - phones: the fictional `555-0100`–`555-0199` range, any format (e.g. `5555550100`, `+1 201-555-0100`)
  - session values: zeroed (`JSESSIONID=000…`, `00000000-0000-0000-0000-000000000000`, `OFBiz.Visitor=10000`)
- Note: a 10-digit numeric ID shaped like a NANP phone number will trip the phone check — use a different length or a leading `0`

Run `bash scripts/internal-leak-check.sh postman/collection.json` before pushing (needs `jq` and GNU `grep -P`). The CI scanners catch many of these, but they are not exhaustive. When in doubt, ask in the PR.

## Reporting issues

- **API bugs / docs improvements**: open a regular issue.
- **Security vulnerabilities**: do NOT open a public issue. See [SECURITY.md](SECURITY.md) for the private disclosure channel.

## Style

- Endpoint descriptions: one-sentence summary, then a paragraph of detail if needed
- Example payloads: minimal but realistic — show what fields are required vs optional
- Response examples: include common success and at least one error case
