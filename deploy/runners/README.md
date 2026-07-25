# Self-hosted GitHub Actions runners

Runners that execute this repo's workflows inside Kubernetes instead of on
GitHub-hosted machines, via [actions-runner-controller][arc] (ARC).

[arc]: https://github.com/actions/actions-runner-controller

> **Which cluster.** These run on the **`docker-desktop`** context. ArgoCD and
> `backstage-dev` live on **`minikube`**. That split is easy to forget and every
> `kubectl` below assumes you are on the right one — check with
> `kubectl config current-context` before you debug something that turns out to
> be in the other cluster.

## What is deployed

| Resource | Purpose |
| --- | --- |
| `RunnerDeployment/self-hosted-runner` | Registers runners against `luniemma/EDX-BACKTAGE` |
| `HorizontalRunnerAutoscaler/self-hosted-runner` | Scales 1–3 replicas on runner busy-ness |

Both live in [runnerdeployment.yaml](runnerdeployment.yaml), in the
`actions-runner-system` namespace.

Runners register with labels `self-hosted`, `Linux`, `X64` and `edx-backtage`.
The first three are automatic; `edx-backtage` is ours, so a workflow can pin to
these runners specifically once a second RunnerDeployment exists.

## Prerequisites

**cert-manager**, which ARC's admission webhooks depend on. It is already
present on `docker-desktop`, installed from manifests rather than Helm:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
```

This is **not** the cert-manager that [deploy/tls-local](../tls-local) manages —
that one is a Helm release on `minikube`, for the local TLS setup. Two clusters,
two independent installs. Do not point the tls-local Terraform at this cluster
expecting it to reconcile this one.

**The controller**, installed with Helm:

```bash
helm repo add actions-runner-controller \
  https://actions-runner-controller.github.io/actions-runner-controller
helm upgrade --install actions-runner-controller \
  actions-runner-controller/actions-runner-controller \
  --namespace actions-runner-system --create-namespace
```

Currently deployed: chart `0.23.7`, controller `v0.27.6`.

**GitHub credentials for the controller.** It authenticates as a PAT or a GitHub
App; this cluster uses a PAT stored as `github_token` in the `controller-manager`
secret. Without it the controller runs happily and no runner ever registers —
see Troubleshooting.

## Deploy

```bash
kubectl apply -f deploy/runners/runnerdeployment.yaml
kubectl get runner -n actions-runner-system -w      # wait for Running
```

Expect roughly 60 seconds from apply to a registered runner: the pod has to pull
the runner image and complete registration before GitHub will hand it a job.

## Verify

[.github/workflows/runner-smoke.yml](../../.github/workflows/runner-smoke.yml)
tests the whole path. Trigger it from the Actions tab, or push a change to the
workflow file.

It does not merely print things — it **asserts** the job ran inside a pod, by
checking for a projected service account token and `KUBERNETES_SERVICE_HOST`. A
GitHub-hosted runner has neither, so the test cannot pass green by accident if
the job lands somewhere unintended.

A healthy run looks like:

```
runner name : self-hosted-runner-v96xs-nhp2f
os / arch   : Linux / X64
namespace   : actions-runner-system
api server  : 10.96.0.1
git         : 2.54.0
docker      : 29.6.2
```

Check both sides independently — the cluster's view and GitHub's view can
disagree, and which one is wrong tells you where the problem is:

```bash
kubectl get runnerdeployment,hra,runner -n actions-runner-system
gh api repos/luniemma/EDX-BACKTAGE/actions/runners \
  --jq '[.runners[]|{name,status,busy,labels:[.labels[].name]}]'
```

## How it behaves

**Ephemeral.** `ephemeral: true` gives every job a fresh pod. Runner pod names
change constantly and that is correct, not a crash loop — confirm with
`kubectl get runner` rather than reading pod age. Without it, one job can leave
state in the work directory for whatever job lands next, which on a public repo
is a route for one pull request to read another's build output.

**Autoscaled 1–3.** The `HorizontalRunnerAutoscaler` owns the replica count, so
the RunnerDeployment deliberately has **no `replicas` field**. Set both and they
fight: the autoscaler scales up, the next `kubectl apply` pins it back down.

Scale-down waits 300s after a scale-up (`scaleDownDelaySecondsAfterScaleOut`).
Tearing runners down the moment a queue drains means the next push pays full pod
startup again.

The metric is `PercentageRunnersBusy`, chosen because it is cheap.
`TotalNumberOfQueuedAndInProgressWorkflowRuns` reacts faster but repeatedly
lists workflow runs and will eat the GitHub API rate limit on a busy repo.

**What's on the image.** `git` and `docker` are present; **`node` is not**.
Workflows needing Node must use `actions/setup-node`, which works fine but
re-downloads each run unless cached.

Docker is available because `dockerEnabled: true`, which costs a **privileged**
dockerd sidecar in every runner pod. If these runners never build images,
`dockerEnabled: false` removes that container outright and is the single biggest
hardening available here.

## Security: this repo is public

Self-hosted runners on public repositories are genuinely dangerous. Anyone who
opens a pull request can execute code on a runner **inside your cluster**, with
whatever that pod can reach. GitHub's own guidance is not to do it.

Right now nothing is exposed: `runner-smoke.yml` triggers only on
`workflow_dispatch` and `push`, never `pull_request`. Keep it that way. Before
moving real CI onto these runners, decide deliberately how forks are handled —
`pull_request_target` and unguarded `pull_request` triggers are the specific
things to avoid.

## Troubleshooting

### Job stuck in "Queued" forever

No runner is registered. The workflow is fine. Check both sides:

```bash
kubectl get runner -n actions-runner-system
gh api repos/luniemma/EDX-BACKTAGE/actions/runners --jq .total_count
```

Common causes, in the order they actually happen:

1. **The manifest was never applied.** `kubectl apply --dry-run=server` runs
   full admission and prints `created` — while persisting *nothing*. It is easy
   to read that as success. `kubectl get runnerdeployment` is the real check.
2. **The controller has no GitHub credentials.** It runs `2/2 Ready` regardless.
   `kubectl logs -n actions-runner-system deploy/actions-runner-controller`.
3. **A label mismatch.** `runs-on:` asks for a label the runner does not have.
   Compare against the registered labels; ARC adds no custom label unless
   `spec.template.spec.labels` sets one.

**`timeout-minutes` will not rescue a queued job.** It starts counting when a
job begins executing, not while it waits for a runner. GitHub cancels jobs
queued longer than 24 hours. To clear one now: `gh run cancel <run-id>`.

### Admission webhook rejects the manifest

```
admission webhook "mutate.runnerdeployment.actions.summerwind.dev" denied the request:
json: cannot unmarshal string into Go struct field
RunnerTemplate.spec.template.spec of type v1alpha1.RunnerSpec
```

This is almost always **a missing space after a colon**:

```yaml
      repository:luniemma/EDX-BACKTAGE     # parses as one plain string
      repository: luniemma/EDX-BACKTAGE    # parses as a mapping
```

Without the space, `spec.template.spec` is a scalar rather than a mapping, and
the webhook fails to unmarshal a string into `RunnerSpec`. The message points at
the Go type, which sends people looking at their values instead of their
whitespace.

Generally: whenever a webhook says *"cannot unmarshal string into Go struct field
X"*, the YAML at `X` collapsed into a scalar. Confirm before editing:

```bash
# safe_load_all, not safe_load — the file holds two documents
python -c "
import yaml
d=[x for x in yaml.safe_load_all(open('deploy/runners/runnerdeployment.yaml'))
   if x['kind']=='RunnerDeployment'][0]
print(type(d['spec']['template']['spec']))"     # want dict, not str
```

Validate against the live webhook without persisting anything:

```bash
kubectl apply -f deploy/runners/runnerdeployment.yaml --dry-run=server
```

### Checking what the CRDs actually support

ARC's field set varies by version, and guessing produces manifests that apply
cleanly while silently dropping what you wrote. Ask the cluster:

```bash
kubectl get crd runnerdeployments.actions.summerwind.dev -o json | python -c "
import json,sys
p=json.load(sys.stdin)['spec']['versions'][0]['schema']['openAPIV3Schema']
print(', '.join(sorted(
  p['properties']['spec']['properties']['template']['properties']['spec']['properties'])))"
```

## Removing it

```bash
kubectl delete -f deploy/runners/runnerdeployment.yaml
```

Runners deregister from GitHub on their own. If a stale entry lingers, remove it
under **Settings → Actions → Runners**.
