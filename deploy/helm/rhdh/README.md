# Red Hat Developer Hub

A thin wrapper around Red Hat's RHDH chart. This chart contributes no workloads
of its own — it pins the dependency, holds the values, and fails the render on
the misconfigurations the upstream chart happily accepts
(`templates/validate.yaml`).

```
Chart.yaml            dependency pin (RHDH chart 7.0.1) + appVersion (RHDH 1.10.3)
values.yaml           shared: image, dynamic plugins, app-config
values-dev.yaml       minikube/kind, in-cluster PostgreSQL
values-staging.yaml   EKS, RDS, external secrets
values-prod.yaml      EKS, RDS, external secrets, HPA + PDB + zone spread
templates/            render-time guards and NOTES only
```

## Why the values are nested three deep

`backstage.upstream.backstage.<thing>` is not a typo. Red Hat publishes the RHDH
chart under the entry name **`backstage`**, and inside it the vanilla Backstage
chart is a dependency aliased **`upstream`**, whose own values live under
**`backstage`**. So:

| key | what it configures |
| --- | --- |
| `global.*` | Helm globals — reach RHDH, Backstage and PostgreSQL alike |
| `backstage.route`, `backstage.test` | RHDH's own additions |
| `backstage.upstream.ingress` | the Ingress |
| `backstage.upstream.postgresql` | the in-cluster database |
| `backstage.upstream.backstage.*` | the Deployment: image, replicas, probes, env, app-config |

## Local render

```bash
helm dependency build deploy/helm/rhdh

helm template rhdh deploy/helm/rhdh \
  -f deploy/helm/rhdh/values.yaml \
  -f deploy/helm/rhdh/values-dev.yaml
```

`dependency build` respects `Chart.lock`; `dependency update` would silently
move the pin.

## Secrets

This chart never creates a Secret. Every environment names one it expects to
already exist, via `global.edx.existingSecret`.

```bash
kubectl -n rhdh-dev create secret generic rhdh-dev-secrets \
  --from-literal=AUTH_GITHUB_CLIENT_ID=... \
  --from-literal=AUTH_GITHUB_CLIENT_SECRET=... \
  --from-literal=GITHUB_TOKEN=...
```

For staging and prod the same Secret also carries the database password and the
service-to-service token, and the key names differ in style because the chart
reads those two by key rather than as environment variables:

```
postgres-password          database password  (global.postgresql.auth)
backend-secret             openssl rand -base64 32  (global.auth.backend)
AUTH_GITHUB_CLIENT_ID      env var, name must match exactly
AUTH_GITHUB_CLIENT_SECRET  env var
GITHUB_TOKEN               env var, optional
```

There is no guest sign-in. Without a valid GitHub OAuth app the backend fails to
start, which is deliberate — see the root README.

## Dynamic plugins

`global.dynamic` in `values.yaml` is what `packages/backend/src/index.ts` used to
be. Anything that was a `backend.add(import(...))` line is either core to the
RHDH image or an entry there, addressed by its path inside the image:

```yaml
- package: ./dynamic-plugins/dist/backstage-plugin-techdocs-backend-dynamic
  disabled: false
```

`includes: [dynamic-plugins.default.yaml]` pulls in the image's own manifest of
every wrapped plugin and its default state; entries in `plugins` override it by
package path. The catalogue of available packages is the `dynamic-plugins/wrappers`
directory of [redhat-developer/rhdh](https://github.com/redhat-developer/rhdh/tree/release-1.10/dynamic-plugins/wrappers)
at the matching release branch — a name that is not there cannot be enabled by
config alone.

Two are deliberately off:

- **GithubEntityProvider** and **GithubOrgEntityProvider** both require a GitHub
  *organisation*. `luniemma` is a personal account, so enabling them today gives
  a provider that errors on every scheduled run. Turning them on is what retires
  `examples/org.yaml`: the sign-in resolver is `usernameMatchingUserEntityName`,
  so a `User` entity has to exist for everyone who signs in, and today those are
  hand-written placeholders.

Enabling a plugin costs startup time — the `install-dynamic-plugins` init
container downloads and unpacks each one before the backend starts.

## Kubernetes plugin

The plugin is enabled with an empty cluster list, which gives a working but
empty Kubernetes tab. To point it at a cluster, add to
`appConfig.kubernetes.clusterLocatorMethods[0].clusters`:

```yaml
- name: dev
  url: https://kubernetes.default.svc
  authProvider: serviceAccount
  serviceAccountToken: ${K8S_SA_TOKEN}
  skipTLSVerify: false
  caData: ${K8S_CA_DATA}
```

and add the matching entries to `extraEnvVars` — note that list **replaces** the
chart's default rather than appending, so the existing entries have to stay.

## Upgrading RHDH

Three fields move together, and CI fails the PR if they disagree:

- `Chart.yaml` → `appVersion`
- `values.yaml` → `backstage.upstream.backstage.image.tag`
- `values.yaml` → `global.catalogIndex.image.tag`

Then re-pin the chart itself if a newer one shipped:

```bash
helm repo update redhat-developer
helm search repo redhat-developer/backstage --versions | head
# edit dependencies[0].version in Chart.yaml, then:
helm dependency update deploy/helm/rhdh   # regenerates Chart.lock
```

Check the wrapper list at the new release branch before upgrading — plugins are
added and removed between releases, and a `package:` path that disappears makes
the init container fail rather than warn.

### The chart this is pinned to is deprecated

On 2026-08-24 Red Hat marked the `backstage` chart deprecated in favour of a
restructured one named `redhat-developer-hub`, with a much flatter values schema
(`image`, `appConfig`, `ingress`, `dynamicPlugins` all at the top level — no
`upstream.backstage` nesting). It is **not** adopted here because its appVersion
is 2.1.0, a product release that does not exist yet: there is no 2.x tag on
`quay.io/rhdh-community/rhdh`, only `next`.

Move when RHDH 2.x ships a numbered image. The values in this directory map onto
the new schema almost key-for-key; the nesting is the main thing that changes.

## Community vs supported image

`quay.io/rhdh-community/rhdh` is the community build — same code, no
subscription, no pull secret, and no Red Hat support. The supported equivalent is
`registry.redhat.io/rhdh/rhdh-hub-rhel9` at the same tag, which needs an active
subscription and an `imagePullSecrets` entry in every namespace. Switching is two
fields in `values.yaml` plus the pull secret.
