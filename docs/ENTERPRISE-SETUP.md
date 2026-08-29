# Enterprise Backstage on Kubernetes, with GitHub / Azure / AWS auth

> **This guide predates the migration to Red Hat Developer Hub and has not been
> rewritten.** It is kept because the *sequence* — database, secrets, base URLs,
> identity, permissions, ownership — is still the right order to do things in.
> The mechanics have changed:
>
> - **File paths are dead.** Every reference to `packages/`, `Dockerfile`,
>   `app-config.yaml`, `app-config.production.yaml` and `deploy/helm/backstage`
>   points at a source tree that no longer exists. Config now lives in
>   `deploy/helm/rhdh/values.yaml` under
>   `backstage.upstream.backstage.appConfig`.
> - **"Add a plugin" is no longer `yarn add` + a line in `index.ts`.** It is an
>   entry under `global.dynamic.plugins` naming a plugin already inside the RHDH
>   image. A plugin Red Hat does not wrap cannot be added by configuration at
>   all — it has to be built and published as a dynamic plugin to an OCI
>   registry.
> - **Several steps are already done.** Guest access is gone and GitHub OAuth is
>   the only way in (steps 7, 9, 10); the frontend sign-in page is now the
>   `signInPage: github` config key rather than React in `App.tsx`.
> - **Step 12 changes shape.** There is no allow-all policy module to replace;
>   RHDH's answer is the RBAC dynamic plugin plus a policy, and the permission
>   framework currently ships disabled.
>
> `deploy/helm/rhdh/README.md` is the accurate reference for anything
> configuration-shaped.

A step-by-step guide taking this repo from "runs in dev with a guest login" to
something an organisation can sign in to.

Fifteen steps, in dependency order. Each states its goal, the actions, and a
**Verify** command — do not move on until it passes, because most failures here
surface several steps later as something unrelated.

[ENTERPRISE-ROADMAP.md](ENTERPRISE-ROADMAP.md) covers *why* and *in what order*,
including budget and sequencing. This is the implementation companion: exact
files, config, and cluster objects.

## Contents

**Part 0 — [Prerequisites](#part-0-prerequisites)** · [Rules](#the-rules-this-guide-enforces)

**Part 1 — Platform**
[1. External database](#step-1-move-off-the-in-cluster-database) ·
[2. Secret management](#step-2-stand-up-secret-management) ·
[3. Remediate committed secrets](#step-3-remediate-what-is-already-committed) ·
[4. Base URLs](#step-4-set-externally-reachable-base-urls) ·
[5. Deploy](#step-5-deploy)

**Part 2 — Identity**
[6. Users and groups](#step-6-ingest-users-and-groups) ·
[7. GitHub OAuth](#step-7-github-oauth) ·
[8. Azure / Entra ID](#step-8-azure-and-entra-id) ·
[9. Sign-in page](#step-9-add-the-frontend-sign-in-page) ·
[10. Remove guest](#step-10-remove-guest-access) ·
[11. AWS workload identity](#step-11-aws-workload-identity-irsa) ·
[12. Permission policy](#step-12-replace-the-allow-all-permission-policy)

**Part 3 — Governance**
[13. Ownership model](#step-13-fix-the-ownership-model) ·
[14. Groups and organizations](#step-14-structure-groups-and-organizations) ·
[15. Keeping it true](#step-15-keep-it-true-over-time)

**Reference** — [What the backend already runs](#what-the-backend-already-runs) ·
[What the frontend already runs](#what-the-frontend-already-runs) ·
[How changes reach the cluster](#how-changes-reach-the-cluster)

[Troubleshooting](#troubleshooting) ·
[Appendix: AWS as an identity provider](#appendix-aws-as-an-identity-provider)

---

## Where this repo actually starts

Read this first, because several steps are "add the thing that isn't there"
rather than "change a setting":

| | Current state |
| --- | --- |
| Backend auth providers | **Only `guest`** registered in [index.ts:27-29](../packages/backend/src/index.ts#L27-L29) |
| GitHub provider package | A dependency, **never registered** — installed but inert |
| Microsoft/Azure provider | Not installed at all |
| Frontend `SignInPage` | **Not configured** in `packages/app/src/App.tsx` |
| `auth.providers` in production | `guest: {}` only |
| User/Group entities | Static `examples/org.yaml`, not the real org |
| Ownership | Everything owned by `group:default/guests` — see [Step 13](#step-13-fix-the-ownership-model) |
| Secrets | **Committed to git** — see [Step 3](#step-3-remediate-what-is-already-committed) |

One thing works in your favour: the Deployment uses `envFrom` on the whole
ConfigMap and whole Secret
([deployment.yaml:54-58](../deploy/helm/backstage/templates/deployment.yaml#L54-L58)),
so any key added to either becomes an environment variable automatically. You
never edit the Deployment to add config.

## What the backend already runs

Backstage's new backend system registers plugins with `backend.add(import(...))`
in [packages/backend/src/index.ts](../packages/backend/src/index.ts). Most of
what an enterprise install needs is already installed — the gaps are config and
policy, not missing packages:

| Area | Registered | Enterprise gap |
| --- | --- | --- |
| Catalog | `catalog-backend` + scaffolder-entity-model, logs | No org ingestion — [Step 6](#step-6-ingest-users-and-groups) |
| Scaffolder | `scaffolder-backend` + github, notifications | — |
| TechDocs | `techdocs-backend` | Local builder cannot run in-cluster — [Step 11](#step-11-aws-workload-identity-irsa) |
| Auth | `auth-backend` + **guest only** | Real providers — [7](#step-7-github-oauth), [8](#step-8-azure-and-entra-id) |
| Permissions | `permission-backend` + **allow-all-policy** | **Every check returns allow** — [Step 12](#step-12-replace-the-allow-all-permission-policy) |
| Search | `search-backend`, pg engine, catalog + techdocs collators | Postgres-backed, so [Step 1](#step-1-move-off-the-in-cluster-database) matters |
| Kubernetes | `kubernetes-backend` | Inert without a `kubernetes:` config block and cluster credentials |
| Notifications / Signals | both registered | — |
| MCP actions | `mcp-actions-backend` | Exposes scaffolder actions over MCP — review before production |
| Proxy | `proxy-backend` | Any `proxy.endpoints` credentials come from the store ([Rule 1](#the-rules-this-guide-enforces)) |

Adding a plugin is two things — install, then register:

```bash
yarn --cwd packages/backend add @backstage/plugin-<name>
```

```ts
// packages/backend/src/index.ts
backend.add(import('@backstage/plugin-<name>'));
```

A backend plugin with no frontend counterpart works over the API and shows
nothing in the UI, which is a common source of "I installed it and nothing
happened".

## What the frontend already runs

`packages/app/src/App.tsx` is seven lines, which is misleading — it does far
more than it appears to:

```tsx
import { createApp } from '@backstage/frontend-defaults';
import catalogPlugin from '@backstage/plugin-catalog/alpha';
import { navModule } from './modules/nav';

export default createApp({
  features: [catalogPlugin, navModule],
});
```

**This is the new frontend system**, not the legacy one. Two consequences worth
internalising before changing anything:

**Plugins are discovered, not listed.** `app-config.yaml:6` sets
`app.packages: all`, which discovers every frontend plugin in
`packages/app/package.json` automatically. So scaffolder, techdocs, search,
kubernetes, org, api-docs, catalog-graph, catalog-import, notifications, signals
and user-settings are all live despite only `catalogPlugin` being named in
`features`. Adding a frontend plugin is usually just:

```bash
yarn --cwd packages/app add @backstage/plugin-<name>
```

For an enterprise install this cuts both ways: it also enables anything that
arrives as a transitive dependency. If you want that controlled, replace
`packages: all` with an explicit list and accept the maintenance.

**Configuration happens in `app.extensions`,** not in code. That is how the
catalog is mounted at `/` rather than `/catalog`:

```yaml
app:
  extensions:
    - page:catalog:
        config:
          path: /
```

Anything you would previously have expressed as JSX routing is now an extension
override here.

**Custom UI is a frontend module.** `modules/nav` shows the pattern — a
`createFrontendModule` contributing a `NavContentBlueprint` extension, added to
`features`. The sidebar explicitly orders `page:catalog` and `page:scaffolder`,
then `nav.rest({ sortBy: 'title' })` for everything else, so a newly discovered
plugin appears in the sidebar automatically without an edit.

[Step 9](#step-9-add-the-frontend-sign-in-page) uses this same pattern for the
sign-in page.

**Branding is still the scaffold default.** `app.title` reads
`Scaffolded Backstage App`. Change it before anyone else sees the portal.

## How changes reach the cluster

Everything below is delivered through Helm, ArgoCD and GitHub Actions — nothing
in this guide is applied by hand except the one-time bootstrap in
[Step 5](#step-5-deploy). But there are **two different paths**, with very
different latency, and knowing which one a given change takes is the difference
between "it deployed" and "ArgoCD says Synced and nothing happened".

| You changed | Path | Rebuild? |
| --- | --- | --- |
| `app-config*.yaml` | Actions → image → tag bump → ArgoCD | **Yes** |
| `packages/**`, `plugins/**` | Actions → image → tag bump → ArgoCD | **Yes** |
| `examples/**`, `templates/**` | Actions → image → tag bump → ArgoCD | **Yes** |
| `deploy/helm/**` values | git → ArgoCD sync | No |
| Secrets | external store → ESO → Secret | No |
| Catalog entities in other repos | catalog refresh loop | No |

**Why config needs a rebuild.** `app-config*.yaml`, `examples/` and `templates/`
are **copied into the image** ([Dockerfile:71-75](../Dockerfile#L71-L75)), and
the chart mounts no ConfigMap for them — its only volume is an `emptyDir` at
`/tmp`. So adding an auth provider in
[Step 7](#step-7-github-oauth) is a code change in every practical sense: commit
it, let `cd-dev.yml` build and push the image, let it bump `image.tag` in
`values-dev.yaml`, and let ArgoCD sync that. Editing `app-config.production.yaml`
and waiting for ArgoCD alone will never take effect.

Only the chart's inputs — `env`, `serviceAccount.annotations`,
`secrets.existingSecret`, ingress, replicas — deploy on an ArgoCD sync with no
rebuild.

> **Known gap: `templates/**` does not trigger a build.** The Dockerfile copies
> `templates/` into the image, but the `paths:` filter in
> [cd-dev.yml:6-15](../.github/workflows/cd-dev.yml#L6-L15) does not list it. So
> editing a software template produces **no** rebuild, and the change reaches
> the portal only when some unrelated commit happens to trigger one. Add
> `templates/**` to that filter.

**Where the ExternalSecret lives.** It is a manifest like any other — put it
under `deploy/` and let ArgoCD own it, rather than `kubectl apply`-ing it
([Rule 2](#the-rules-this-guide-enforces)). The *values* stay in the external
store; only the pointer is in git.

**Bootstrap is the exception.** Installing ArgoCD, cert-manager and ESO, and
applying the first `Application`, cannot themselves be GitOps-managed — the
loop has to start somewhere. Keep that set as small as
[Step 5](#step-5-deploy), and manage everything after it declaratively; an
app-of-apps pattern reduces the hand-applied set to a single root Application.

---

## The rules this guide enforces

Five rules. Everything below follows from them, and every shortcut that gets
skipped later violates one of them.

1. **No secret value in git — in any environment, including dev.** One
   mechanism everywhere: an external store owns the material.
   ([Step 2](#step-2-stand-up-secret-management))
2. **No ad-hoc cluster objects.** If a Secret exists and no manifest or store
   entry explains it, that is an incident, not a configuration.
   ([Step 2](#step-2-stand-up-secret-management))
3. **Identity before providers.** Sign-in resolvers need `User` entities to
   resolve *to*. Ingest users first, or sign-in succeeds and ownership silently
   resolves to nothing. ([Step 6](#step-6-ingest-users-and-groups))
4. **Federate, never store long-lived credentials.** IRSA and OIDC over static
   keys, every time. ([Step 11](#step-11-aws-workload-identity-irsa))
5. **Groups own things; the directory owns groups.** Never make a person the
   owner — that entity is orphaned the day they leave. And never hand-edit
   `org.yaml`, because the next sync overwrites it.
   ([Step 13](#step-13-fix-the-ownership-model),
   [14](#step-14-structure-groups-and-organizations))

---

# Part 0: Prerequisites

## Tools

| Tool | Version | Check |
| --- | --- | --- |
| `kubectl` | ≥ 1.28 | `kubectl version --client -o json` |
| `helm` | ≥ 3.12 | `helm version --short` |
| `yarn` | 4.x via corepack | `yarn --version` |
| Node | 22 or 24 (**not** 26) | `node --version` |
| `gh` | any | `gh auth status` |
| `argocd` (optional) | matches server | `argocd version --client` |

Node 26 is not supported by Backstage 1.53. Dependabot will propose it; see the
root README.

## Cluster

- Kubernetes ≥ 1.28 with a working ingress controller
- **cert-manager** installed, with a working `ClusterIssuer`
- **ArgoCD** installed — [deploy/argocd/README.md](../deploy/argocd/README.md)
- **External Secrets Operator** installed — this guide assumes it from Step 2
- A **managed** Postgres reachable from the cluster (RDS, Cloud SQL, Azure
  Database). Nothing in `terraform/` provisions this yet.
- A container registry the cluster can pull from

## Access you need

Gather these before starting; each blocks a specific step and they often need
someone else's approval.

| Access | Needed for |
| --- | --- |
| Admin on the GitHub org | OAuth app + `read:org` token ([7](#step-7-github-oauth), [6](#step-6-ingest-users-and-groups)) |
| Entra ID app registration rights | Azure provider ([8](#step-8-azure-and-entra-id)) |
| Write access to the secret store | Every step from [2](#step-2-stand-up-secret-management) on |
| IAM permission to create roles + trust policies | IRSA ([11](#step-11-aws-workload-identity-irsa)) |
| DNS control for the Backstage hostname | [4](#step-4-set-externally-reachable-base-urls), and OAuth callbacks |

## Verify prerequisites

```bash
kubectl version --client -o json | head -5
kubectl get clusterissuer                                  # expect at least one Ready
kubectl get deploy -n cert-manager                         # expect 3, all Ready
kubectl get deploy -n argocd argocd-server                 # expect Ready
kubectl get crd externalsecrets.external-secrets.io        # expect it to exist
node --version                                             # v22.x or v24.x
```

If the ESO CRD is missing, install it before Step 2 — the rest of the guide
depends on it:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace
```

---

# Part 1: Platform

## Step 1: Move off the in-cluster database

**Goal:** production data on a managed instance with backups and failover.

`values-dev.yaml` sets `postgres.enabled: true`, bringing up a single-pod
StatefulSet with neither. That is a dev convenience only.

In `values-staging.yaml` and `values-prod.yaml`:

```yaml
postgres:
  enabled: false
externalPostgres:
  host: backstage.abc123.us-east-1.rds.amazonaws.com
  user: backstage
env:
  POSTGRES_PORT: "5432"
```

`externalPostgres` accepts **only** `host` and `user`
([values.yaml:118-120](../deploy/helm/backstage/values.yaml#L118-L120)). The port
comes from `env.POSTGRES_PORT`, and there is **no external `database` key** —
`postgres.auth.database` applies only to the in-cluster StatefulSet. Adding
`database:` under `externalPostgres` looks right and does nothing; extend
[_helpers.tpl](../deploy/helm/backstage/templates/_helpers.tpl) and the ConfigMap
if you need a non-default name.

**Verify** — the chart refuses to render with neither configured
([_helpers.tpl:93](../deploy/helm/backstage/templates/_helpers.tpl#L93)), so a
successful render proves the wiring:

```bash
helm template backstage deploy/helm/backstage \
  -f deploy/helm/backstage/values.yaml \
  -f deploy/helm/backstage/values-prod.yaml | grep -A2 POSTGRES_HOST
```

## Step 2: Stand up secret management

**Goal:** no credential in this repository, in any environment.

> **Rule 1.** Not a placeholder someone will fill in, not a "dev-only"
> password. Allow one environment a committed secret and the pattern is
> established; the next inherits it.

Set this in **every** values file — dev, staging and prod alike:

```yaml
secrets:
  create: false
  existingSecret: backstage-secrets
```

No chart change is needed. `backstage.secretName`
([_helpers.tpl:64-70](../deploy/helm/backstage/templates/_helpers.tpl#L64-L70))
already prefers `existingSecret`, and `envFrom` reads whatever keys it contains.

Create the store entry with every key the app needs, per environment:

```
POSTGRES_PASSWORD              BACKEND_SECRET
GITHUB_TOKEN                   AUTH_GITHUB_CLIENT_ID
AUTH_GITHUB_CLIENT_SECRET      AUTH_MICROSOFT_CLIENT_ID
AUTH_MICROSOFT_CLIENT_SECRET   AUTH_MICROSOFT_TENANT_ID
```

Then project it:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: backstage-secrets
  namespace: backstage-prod
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: backstage-secrets
  dataFrom:
    - extract:
        key: backstage/prod
```

`dataFrom.extract` projects **every** key in the entry, so adding a provider
later means writing one more key to the store — no manifest edit, no redeploy,
and the change is visible in the store's audit log rather than in a diff.

Pair `refreshInterval` with [Reloader](https://github.com/stakater/Reloader) so
the Deployment restarts when the Secret changes. Without it the pod keeps the
old value until something unrelated restarts it, and you will believe you have
rotated when you have not.

### No ad-hoc secret creation

> **Rule 2.** `kubectl create secret` is not a shortcut, it is a different and
> worse system — no record of who created it or when, silent drift between
> environments, no scheduled rotation, and reproducing an environment becomes an
> exercise in asking people what they remember typing.

This repo has the failure mode on file. `ecr-creds` was created by hand, which
duplicated the credential into a `kubectl.kubernetes.io/last-applied-configuration`
annotation and — because ECR tokens expire after 12 hours — kept working until
the next pod restart, then failed with an image-pull error pointing nowhere near
the cause. ESO's ECR authorization-token generator handles that case properly.

**Verify:**

```bash
kubectl get externalsecret backstage-secrets -n backstage-prod \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'      # want True
kubectl get secret backstage-secrets -n backstage-prod \
  -o json | jq -r '.data | keys[]'                                   # want every key above
```

## Step 3: Remediate what is already committed

**Goal:** the secrets currently in git are rotated and removed.

Not hypothetical. Three values are committed today and live in the dev cluster:

```
deploy/helm/backstage/values-dev.yaml:40  postgresPassword: "postgres"
deploy/helm/backstage/values-dev.yaml:41  backendSecret: "dev-only-not-a-real-secret-please-rotate"
deploy/helm/backstage/values.yaml:131     password: postgres
```

Treat them as compromised — the repo is public, and git history keeps them after
deletion.

1. Rotate each value **in the store first**
2. Then delete the keys from the values files

Deleting without rotating changes nothing. `.gitleaks.toml` already runs in CI;
check its allowlist is not what let these through.

**Verify:**

```bash
grep -rn "postgresPassword\|backendSecret\|password:" deploy/helm/backstage/values*.yaml
# expect no assigned values — keys removed entirely
```

## Step 4: Set externally reachable base URLs

**Goal:** the browser can reach exactly the URL Backstage advertises.

> **Fix this before setting any values.** `app-config.production.yaml`
> **hardcodes `http://localhost:7007`** for both `app.baseUrl` and
> `backend.baseUrl`, and never reads the environment. The chart dutifully sets
> `APP_BASE_URL` and `BACKEND_BASE_URL` in every values file — and every one of
> them is ignored. The deployed portal advertises `localhost:7007` to browsers.

Parameterise the config first:

```yaml
# app-config.production.yaml
app:
  baseUrl: ${APP_BASE_URL}
backend:
  baseUrl: ${BACKEND_BASE_URL}
  cors:
    origin: ${APP_BASE_URL}
```

Only then do the values take effect:

```yaml
env:
  APP_BASE_URL: https://backstage.example.com
  BACKEND_BASE_URL: https://backstage.example.com
```

The **browser** uses these verbatim — scheme, host and port must match how a
user actually reaches the portal. This is the most common cause of "the page
loads but every API call fails", and it matters more from Step 7, because OAuth
callback URLs must match too.

**Verify** — check the running pod rather than the values file, since that is
where the two disagree today:

```bash
kubectl exec -n backstage-prod deploy/backstage -- printenv APP_BASE_URL
curl -s https://backstage.example.com/api/app/config | grep -o '"baseUrl":"[^"]*"'
# both must show the external URL, never localhost
```

## Step 5: Deploy

```bash
kubectl apply -f deploy/argocd/project.yaml
kubectl apply -f deploy/argocd/application-prod.yaml
```

Allow a couple of minutes: Backstage initialises every plugin and runs its own
Knex migrations before reporting ready.

**Verify:**

```bash
kubectl get application backstage-prod -n argocd     # Synced / Healthy
kubectl get pods -n backstage-prod                   # Running, not CrashLoopBackOff
```

A crash loop here is usually a missing Secret key from Step 2 — Backstage fails
at **startup** when a `${VAR}` resolves empty, which is deliberate. Check with
`kubectl logs`.

---

# Part 2: Identity

## How Backstage auth fits together

Each provider needs **four** pieces. Miss one and the failure is confusing
rather than clear:

1. A **backend module** registered in `packages/backend/src/index.ts`
2. **`auth.providers.<name>`** config with credentials from env
3. A **`SignInPage`** in the frontend offering that provider
4. A **sign-in resolver** mapping the external identity to a catalog `User`

Steps 6–9 deliver these in the only order that works.

## Step 6: Ingest users and groups

**Goal:** real `User` and `Group` entities exist before any provider points at
them.

> **Rule 3.** This comes first. Resolvers need entities to resolve *to* —
> without them sign-in succeeds and every ownership check silently resolves to
> nothing. Doing this after the provider means shipping a portal that appears to
> work and does not.

Replace the static `examples/org.yaml`:

- **GitHub** — add `GithubOrgEntityProvider`, needs a token with `read:org`
- **Entra ID** — add `@backstage/plugin-catalog-backend-module-msgraph`, which
  pulls users and groups from Microsoft Graph on a schedule

While here, fix a related problem: `app-config.production.yaml` overrides
`catalog.locations` wholesale and lists only the three `examples/` files, so
**the golden-path template is invisible in the deployed portal**. Add it:

```yaml
catalog:
  locations:
    - type: file
      target: ./templates/golden-path-service/template.yaml
      rules:
        - allow: [Template]
```

**Verify** — this is the gate for everything that follows:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://backstage.example.com/api/catalog/entities?filter=kind=user' | jq length
```

Non-zero means resolvers have targets. Zero means do not proceed to Step 7.

## Step 7: GitHub OAuth

**Goal:** users sign in with GitHub.

The natural fit here — the catalog and scaffolder already integrate with GitHub,
so the org is already the source of truth.

**Register the OAuth app** (Settings → Developer settings → OAuth Apps):

```
Homepage URL:               https://backstage.example.com
Authorization callback URL: https://backstage.example.com/api/auth/github/handler/frame
```

The `/handler/frame` suffix is required. Without it the callback fails *after*
the user has authorised, which reads like a Backstage bug rather than a config
error.

**Store the credentials** — write `AUTH_GITHUB_CLIENT_ID` and
`AUTH_GITHUB_CLIENT_SECRET` to the store entry from Step 2. Never to a values
file.

**Register the module** — the package is already a dependency:

```ts
// packages/backend/src/index.ts
backend.add(import('@backstage/plugin-auth-backend-module-github-provider'));
```

**Configure it:**

```yaml
auth:
  environment: production
  providers:
    github:
      production:
        clientId: ${AUTH_GITHUB_CLIENT_ID}
        clientSecret: ${AUTH_GITHUB_CLIENT_SECRET}
        signIn:
          resolvers:
            - resolver: usernameMatchingUserEntityName
```

**Verify:**

```bash
curl -s https://backstage.example.com/api/auth/github/start | head -5
```

## Step 8: Azure and Entra ID

**Goal:** users sign in with Microsoft. Skip if GitHub is your only IdP.

**Register the app** (Entra ID → App registrations):

```
Redirect URI (Web): https://backstage.example.com/api/auth/microsoft/handler/frame
API permissions:    Microsoft Graph → User.Read, offline_access
                    (add GroupMember.Read.All to ingest groups)
```

Note the **tenant ID**, **client ID**, and a generated **client secret**, and
write all three to the store.

**Install and register the module** — not currently a dependency:

```bash
yarn --cwd packages/backend add @backstage/plugin-auth-backend-module-microsoft-provider
```

```ts
backend.add(import('@backstage/plugin-auth-backend-module-microsoft-provider'));
```

**Configure it:**

```yaml
auth:
  providers:
    microsoft:
      production:
        clientId: ${AUTH_MICROSOFT_CLIENT_ID}
        clientSecret: ${AUTH_MICROSOFT_CLIENT_SECRET}
        tenantId: ${AUTH_MICROSOFT_TENANT_ID}
        signIn:
          resolvers:
            - resolver: emailMatchingUserEntityProfileEmail
```

Entra identities are email-shaped, so match on profile email.
`usernameMatchingUserEntityName` will not resolve against `user@company.com` —
using GitHub's resolver here is a common and confusing mistake.

## Step 9: Add the frontend sign-in page

**Goal:** users can actually see the providers.

Backend config alone changes nothing visible.

> **This app uses the new frontend system.** Most Backstage sign-in
> documentation you will find shows the legacy pattern —
> `createApp({ components: { SignInPage } })` from `@backstage/core-app-api`.
> That does not apply here. `App.tsx` imports `createApp` from
> `@backstage/frontend-defaults`, which takes `features`, not `components`.
> Pasting the legacy snippet produces a config that is silently ignored.

Sign-in is an **extension**, contributed through a frontend module in the same
shape as the existing `navModule`:

```tsx
// packages/app/src/modules/auth/index.ts
import { createFrontendModule } from '@backstage/frontend-plugin-api';
import { SignInPageBlueprint } from '@backstage/frontend-plugin-api';

const signInPage = SignInPageBlueprint.make({
  params: {
    loader: async () => {
      const { SignInPage } = await import('@backstage/core-components');
      const { githubAuthApiRef, microsoftAuthApiRef } = await import(
        '@backstage/core-plugin-api'
      );
      return props => (
        <SignInPage
          {...props}
          providers={[
            {
              id: 'github-auth-provider',
              title: 'GitHub',
              message: 'Sign in with GitHub',
              apiRef: githubAuthApiRef,
            },
            {
              id: 'microsoft-auth-provider',
              title: 'Microsoft',
              message: 'Sign in with Entra ID',
              apiRef: microsoftAuthApiRef,
            },
          ]}
        />
      );
    },
  },
});

export const authModule = createFrontendModule({
  pluginId: 'app',
  extensions: [signInPage],
});
```

Then register it exactly like the nav module:

```tsx
// packages/app/src/App.tsx
import { authModule } from './modules/auth';

export default createApp({
  features: [catalogPlugin, navModule, authModule],
});
```

Omit `auto` when offering more than one provider, or the first is chosen without
asking.

> Verify the `SignInPageBlueprint` import path and `params` shape against the
> version of `@backstage/frontend-plugin-api` you have installed — the new
> frontend system's APIs are still moving between releases, and this could not
> be checked here because `node_modules` has no `@backstage` packages (run
> `yarn install` first). The *structure* — an extension in a frontend module
> added to `features` — is what matters and is stable.

**Verify:** sign in as a real user and confirm your avatar and owned entities
appear — that proves the resolver matched a `User` entity, not just that OAuth
succeeded.

## Step 10: Remove guest access

**Goal:** anonymous access is gone.

Guest must be removed deliberately; it does not disappear when you add a real
provider.

```ts
// packages/backend/src/index.ts — delete
backend.add(import('@backstage/plugin-auth-backend-module-guest-provider'));
```

```yaml
# app-config.production.yaml — delete
auth:
  providers:
    guest: {}
```

**Check the live ConfigMap too.** In this cluster someone hand-added
`APP_CONFIG_auth_providers_guest_dangerouslyAllowOutsideDevelopment: "true"`.
Because ArgoCD syncs with `ServerSideApply`, another field manager owns that key
and ArgoCD reports the resource **Synced** while it is still there.

**Verify:**

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  https://backstage.example.com/api/auth/guest/refresh          # want 404

kubectl get cm backstage -n backstage-prod \
  -o jsonpath='{.data.APP_CONFIG_auth_providers_guest_dangerouslyAllowOutsideDevelopment}'
# want empty output
```

## Step 11: AWS workload identity (IRSA)

**Goal:** Backstage calls AWS with no stored credentials.

AWS is **not** a third sign-in button — treating it as one is the usual source
of confusion. It appears here because Backstage needs AWS access for ECR and S3,
not because users authenticate with it. For AWS as an IdP see the
[appendix](#appendix-aws-as-an-identity-provider).

> **Rule 4.** Static access keys are long-lived, do not rotate themselves, and a
> leaked pair stays valid until someone notices. Federate.

The chart already supports the annotation:

```yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::724772096574:role/backstage-prod
```

The role's trust policy federates the service account:

```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::724772096574:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": { "StringEquals": {
    "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE:sub":
      "system:serviceaccount:backstage-prod:backstage"
  }}
}
```

The SDK then picks credentials up with no config — nothing to store, nothing to
rotate, nothing to leak.

On a non-EKS cluster, federate through the cluster's own OIDC issuer or a
workload-identity bridge before reaching for keys. If you are truly stuck with
static keys, they come from the store like everything else and need a rotation
schedule you have actually tested:

```yaml
integrations:
  aws:
    - accountId: "724772096574"
      accessKeyId: ${AWS_ACCESS_KEY_ID}
      secretAccessKey: ${AWS_SECRET_ACCESS_KEY}
```

### TechDocs needs this too

The current config (`builder: local`, `generator.runIn: docker`) **cannot work
in-cluster** — there is no Docker daemon in the pod. Build docs in CI and serve
from S3:

```yaml
techdocs:
  builder: external
  publisher:
    type: awsS3
    awsS3:
      bucketName: backstage-techdocs-prod
      region: us-east-1
```

With IRSA in place this needs no credentials.

**Verify:**

```bash
kubectl exec -n backstage-prod deploy/backstage -- \
  env | grep AWS_ROLE_ARN                    # injected by the EKS webhook
```

---

## Step 12: Replace the allow-all permission policy

**Goal:** authorisation actually restricts something.

The backend registers `permission-backend` together with
`permission-backend-module-allow-all-policy`
([index.ts:42-46](../packages/backend/src/index.ts#L42-L46)). That is more
dangerous than permissions being switched off: the framework is live, the UI
renders permission-aware controls, and every check returns **allow**. It looks
enforced and is not.

This is last because it is the only step that depends on all the others. A
policy can only make decisions about identities and groups that exist, which is
what Steps 6–10 deliver.

```bash
yarn --cwd packages/backend remove @backstage/plugin-permission-backend-module-allow-all-policy
```

```ts
// packages/backend/src/index.ts — delete this
backend.add(
  import('@backstage/plugin-permission-backend-module-allow-all-policy'),
);
// and add your own policy module instead
backend.add(import('./modules/permissionPolicy'));
```

```yaml
permission:
  enabled: true
```

Start narrow: a policy that allows read broadly and restricts destructive
actions — deleting catalog entities, executing scaffolder templates — to entity
owners. `@backstage/plugin-permission-node` provides the ownership helpers, and
group membership from Step 6 is what makes them resolve.

**Verify** — as a user who owns nothing, a destructive action must be refused:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X DELETE \
  -H "Authorization: Bearer $NON_OWNER_TOKEN" \
  'https://backstage.example.com/api/catalog/entities/by-uid/<uid>'
# want 403, not 204
```

A 204 means the allow-all module is still registered, or `permission.enabled`
is still false.

---

# Part 3: Governance

Steps 6–12 make identity real. Governance is what keeps it true six months
later: who owns what, how teams are modelled, and what happens when people join,
move and leave.

## Step 13: Fix the ownership model

**Goal:** every entity has a resolvable owner, expressed one way.

Ownership is the spine of Backstage. Permissions, on-call routing, "who do I ask
about this", and every ownership-aware UI resolve through `spec.owner`. Today
this repo has three problems at once.

**Everything is owned by a placeholder.** Every real entity — the Xeta system,
its components, its resources — is owned by `group:default/guests`, a group
whose only member is the `guest` user and whose `children` is empty:

```bash
grep -rn "owner:" catalog/ examples/ catalog-info.yaml
```

**Owner references use four different formats:**

| Found in | Value | Problem |
| --- | --- | --- |
| `catalog/**` | `group:default/guests` | Correct — canonical form |
| `examples/entities.yaml` | `guests` | Bare name, relies on defaulting |
| `examples/template/**` | `user:guest` | No namespace |
| `catalog-info.yaml:12` | `john@example.com` | **Not an entity reference at all** |

An email is not a resolvable target, so this repo's own component has no working
owner. Standardise on the full form — `<kind>:<namespace>/<name>` — everywhere.
Mixed forms mostly work until an ownership query returns nothing and no error.

**The golden-path template defaults to guests.**
[template.yaml:16](../templates/golden-path-service/template.yaml#L16) sets
`owner: group:default/guests`, so every scaffolded service starts unowned in
practice. Point it at a real platform group.

**Verify** — no entity should reference the placeholder or a bare email:

```bash
grep -rn "owner:" catalog/ examples/ templates/ catalog-info.yaml \
  | grep -v "group:default/" | grep -v '${{'
# expect no output
```

## Step 14: Structure groups and organizations

**Goal:** a group tree that mirrors how the company actually works.

`examples/org.yaml` defines one flat group with `children: []`. Real
organisations need hierarchy, because ownership questions are asked at different
levels — a director wants "everything my department owns", an engineer wants
"my team's services".

```yaml
apiVersion: backstage.io/v1alpha1
kind: Group
metadata:
  name: platform
spec:
  type: department
  children: [platform-infra, platform-developer-experience]
---
apiVersion: backstage.io/v1alpha1
kind: Group
metadata:
  name: platform-infra
spec:
  type: team
  parent: platform
  children: []
```

Conventions worth fixing now rather than after a thousand entities exist:

- **`spec.type`** — settle on a vocabulary (`department`, `team`, `sub-department`)
  and use it consistently; the UI and queries group by it
- **Names** — lowercase and hyphenated, matching the upstream group name in
  GitHub or Entra so the mapping stays mechanical
- **Own with groups, never users** — a person-owned entity becomes orphaned the
  day they leave, which is precisely when you need to know who owns it

> **These entities are generated, not written.** Once
> [Step 6](#step-6-ingest-users-and-groups) is running, GitHub teams or Entra
> groups produce them on a schedule. Hand-editing `org.yaml` afterwards means
> your edits are overwritten at the next refresh — treat the upstream directory
> as the source of truth and fix structure there.

### Multiple organizations

For several GitHub orgs, use `GithubMultiOrgEntityProvider`, which can place each
org's users and groups in its **own namespace** — so `acme/platform` and
`contoso/platform` stay distinct entities rather than colliding.

Namespaces are also the lever for tenant isolation generally: entity references
become `group:acme/platform`, and permission policies can scope decisions by
namespace.

**Verify:**

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://backstage.example.com/api/catalog/entities?filter=kind=group' \
  | jq -r '.[] | "\(.metadata.namespace)/\(.metadata.name) parent=\(.spec.parent // "none")"'
```

Expect a tree, not a flat list of orphans.

## Step 15: Keep it true over time

**Goal:** governance survives contact with joiners, movers and leavers.

**Automate the lifecycle.** With Step 6's provider on a schedule, a leaver
disappears from the directory and their `User` entity goes with it. That is the
point: manual user management drifts within weeks, and the drift is invisible
until someone tries to page a person who left.

Set the refresh frequency deliberately. Hourly is typical; slower means a
departed employee retains resolvable ownership longer.

**Detect orphans continuously.** Entities whose owner no longer resolves are the
governance failure that matters, because they look fine in the UI:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://backstage.example.com/api/catalog/entities?filter=kind=component' \
  | jq -r '.[] | select(.relations | map(select(.type=="ownedBy")) | length == 0)
           | .metadata.name'
```

Run it on a schedule and treat output as a work queue. An entity with no
resolvable owner is unowned regardless of what its YAML says.

**Make ownership non-optional at the door.** The scaffolder already requires an
owner via `OwnerPicker`
([template.yaml:34-41](../templates/golden-path-service/template.yaml#L34-L41)),
which is the right pattern — validated against the catalog at creation time
rather than checked later. Entities registered by other routes need the same
treatment: reject registration without a resolvable group owner.

**Plan handoff explicitly.** Teams reorganise. Changing `spec.owner` is a
one-line PR, so the work is deciding *who accepts* the entity — make that a
required reviewer on the owning group, not an implicit consequence of a merge.

**Connect groups to permissions.** Group membership is what makes
[Step 12](#step-12-replace-the-allow-all-permission-policy) meaningful: policies
express "owners may delete their own entities" and resolve it through the
`ownedBy` relation. Without the hierarchy from Step 14, every policy degrades to
allow-all or deny-all.

**Verify** — the loop is closed when this returns zero:

```bash
# entities whose declared owner does not exist as an entity
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://backstage.example.com/api/catalog/entities?filter=kind=component' \
  | jq '[.[] | select(.relations | map(select(.type=="ownedBy")) | length == 0)] | length'
```

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| Redirect loop after authorising | `APP_BASE_URL` / `BACKEND_BASE_URL` do not match the URL the browser used ([4](#step-4-set-externally-reachable-base-urls)) |
| `Failed to sign in, unable to resolve user identity` | No matching `User` entity — Step 6 skipped or incomplete |
| Callback 404s after the consent screen | Callback URL missing the `/handler/frame` suffix |
| Sign-in works, ownership shows nothing | Users ingested, groups not — add group ingestion |
| Guest still available after removal | Manually patched ConfigMap key ([10](#step-10-remove-guest-access)) |
| `Missing required config value at 'auth.providers...'` | Store key absent, so `${VAR}` resolved empty |
| Pod crash-loops right after a rollout | Same cause — Backstage fails at startup by design |
| Rotated a secret, old value still in use | No Reloader; pod still holds the old env ([2](#step-2-stand-up-secret-management)) |

## Appendix: AWS as an identity provider

There is no first-party AWS sign-in provider. If users live in **Cognito** or
**IAM Identity Center**, expose an OIDC application and use the generic `oidc`
provider:

```bash
yarn --cwd packages/backend add @backstage/plugin-auth-backend-module-oidc-provider
```

```yaml
auth:
  providers:
    oidc:
      production:
        metadataUrl: https://cognito-idp.us-east-1.amazonaws.com/us-east-1_EXAMPLE/.well-known/openid-configuration
        clientId: ${AUTH_OIDC_CLIENT_ID}
        clientSecret: ${AUTH_OIDC_CLIENT_SECRET}
        signIn:
          resolvers:
            - resolver: emailMatchingUserEntityProfileEmail
```

The same provider covers Okta and Google Workspace, so it is the escape hatch
whenever the standard is not GitHub or Entra.

## After this guide

Writing the actual permission policy. [Step 12](#step-12-replace-the-allow-all-permission-policy)
removes the allow-all module and turns the framework on; deciding what each role
may do is a design exercise, not a config change.
[ENTERPRISE-ROADMAP.md](ENTERPRISE-ROADMAP.md) A3 covers the shape of that work.

Two other things this guide deliberately leaves inert:

**The Kubernetes plugin** is registered but has no `kubernetes:` config block, so
it shows nothing. Wiring it means giving Backstage read access to your clusters —
worth doing deliberately, with a scoped ServiceAccount per cluster rather than a
shared admin credential.

**MCP actions** are exposed by `mcp-actions-backend`. Review what that surface
offers before production; `auth.clientIdMetadataDocuments` in `app-config.yaml`
governs which clients may register.
