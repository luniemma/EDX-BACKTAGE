# Migrating PostgreSQL out of the cluster

## What this migration is, and what it is not

It is an **architecture change**, not a data migration. At the time it was
written the in-cluster PostgreSQL and its EBS volume had already been
destroyed, RHDH had never reached Ready, and the database had never held a
single catalog entity. There was nothing to move.

If you are running this against a live cluster with a populated catalog, the
data steps in "Migrating with data" below are not optional.

## Why move at all

The in-cluster profile ran a single PostgreSQL pod on a Spot node with no
backups and no failover. Three consequences, in increasing order of how much
they should bother you:

1. A Spot reclamation restarts the database. RHDH reconnects, but in-flight
   requests fail.
2. The EBS volume is zonal. If the node is replaced in a different AZ the pod
   cannot mount its own data and stays Pending until something schedules it
   back where the volume is.
3. Losing the volume loses the catalog outright, with nothing to restore from.
   This is not hypothetical — that exact volume was orphaned by a teardown and
   deleted by hand.

RDS answers all three: automated backups with a 7-day window, a restorable
final snapshot on destroy, and storage that is not tied to a node's lifecycle.

## What it costs

About **$15/month** on top of the cluster, taking the stack from ~$115 to ~$130.

| Item | ~$/month |
| --- | --- |
| `db.t4g.micro` (2 vCPU burstable, 1 GiB) | 12 |
| 20 GiB gp3 storage | 2 |
| Backup storage within the retention window | ~1 |

Multi-AZ is off. It roughly doubles the instance cost for a standby this
profile does not justify — turn it on before anything depends on the portal
surviving an AZ failure.

## Where it sits

The instance lives in **private subnets with no NAT gateway and no internet
route**. Those subnets are new, and they are free: a subnet costs nothing, only
a NAT gateway does, and RDS needs no outbound access. So the database gets
proper network isolation without reintroducing the $33/month the lean profile
exists to avoid.

Access is granted by **security group reference, not CIDR**. The rule allows
5432 from the cluster's node security group only. Node addresses change every
time the Spot group is replaced, so a CIDR rule would either go stale or have
to be widened to the whole VPC.

`platform-db` is a **separate state key** from `platform`. That is the whole
point: `destroy.yml` tears the cluster down routinely, and a database sharing
that state would go with it every time.

## Order of operations

Apply forwards, destroy backwards. Both are encoded in the workflows.

```
apply:    platform  →  platform-db  →  platform-addons
destroy:  addons    →  platform-db  →  platform
```

The database must be destroyed before the cluster root when it is destroyed at
all: the instance sits in the VPC's private subnets and its security group
references the node security group, so destroying the VPC first fails on
dependencies.

Note the destroy scope: `everything` leaves the database standing.
`everything-including-database` is a separate opt-in, because the database is
the only thing in this stack holding state worth keeping.

## Running it

```
gh workflow run platform.yml --ref main -f root=both
```

Then wire the endpoint into the chart. It is not known until the instance
exists, so it cannot be committed in advance:

```
terraform -chdir=terraform/platform-db output -raw endpoint
```

Put that in `deploy/helm/rhdh/values-lean.yaml` under
`backstage.upstream.backstage.appConfig.backend.database.connection.host`, and
commit — ArgoCD syncs the change. Until it is set, `templates/validate.yaml`
fails the render on purpose: with `postgresql.enabled: false` there is no
in-cluster fallback to silently start against.

Then copy the master password into the Secret RHDH reads. RDS generates and
stores it in Secrets Manager, so it is never in Terraform state:

```
terraform -chdir=terraform/platform-db output -raw kubernetes_secret_command
```

Run that command's output. **Nothing syncs those two automatically** — re-run
it after every password rotation, or install External Secrets Operator and
point it at the secret ARN.

## Migrating with data

Not exercised here, because there was no data. If you are moving a populated
catalog, do not skip these:

1. **Scale RHDH to zero first.** `kubectl -n rhdh-lean scale deploy/rhdh-developer-hub --replicas=0`.
   Dumping a database that Backstage is still writing to gives you a
   torn snapshot, and RHDH writes on a timer even when nobody is using it.
2. **Dump from the pod**, not from outside: the in-cluster instance has no
   external endpoint.
   `kubectl -n rhdh-lean exec rhdh-postgresql-0 -- pg_dumpall -U postgres > dump.sql`
3. **Restore into RDS** from something inside the VPC — a debug pod on the
   cluster — since the instance is not publicly accessible.
4. **Then** flip `postgresql.enabled` to false and set the host. In that order:
   flipping first deletes the StatefulSet, and its PVC is retained but its
   pod is gone, so the dump target disappears.

RHDH creates one database per plugin (`backstage_plugin_catalog`,
`backstage_plugin_auth`, and so on), which is why the dump above is
`pg_dumpall` rather than `pg_dump` — a single-database dump silently leaves
most of the portal's state behind.

## Rolling back

Set `postgresql.enabled: true` in `values-lean.yaml`, restore the `fsGroup: 26`
block, and clear the connection host. The RDS instance is untouched by that,
and `everything` scope teardowns leave it alone, so the rollback is reversible
in both directions until you explicitly destroy the database.
