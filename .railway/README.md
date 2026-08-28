# Railway IaC

[`railway.ts`](railway.ts) is the desired whole-project Railway configuration:
web, worker, PostgreSQL, and a private Bucket in Singapore.

After `pnpm install`, use the repository-pinned Railway CLI:

```sh
railway login
railway link
pnpm run infra:plan
```

Inspect the plan before `pnpm run infra:apply`. Applying mutates the linked
environment and may be destructive; it is never part of normal local checks.
Create the referenced shared secrets and generated web domain in Railway. See
[`docs/deployment.md`](../docs/deployment.md) for bootstrap, verification,
export, backup, and deletion procedures.
