# Logical Dump And Restore

Use CloudNativePG physical backups for disaster recovery and point-in-time
recovery. Use logical dumps when you need portability, selective restore, data
movement between environments or application-level recovery tests.

The `pg_dump` and `pg_restore` client major version should match the PostgreSQL
server major version. The commands below use PostgreSQL `18.4`.

## Dump One Database

```sh
export PGHOST="127.0.0.1"
export PGPORT="5432"
export PGDATABASE="app"
export PGUSER="app"
export PGPASSWORD="<read-from-your-secret-manager>"

kubectl -n data port-forward svc/app-postgres-rw 5432:5432
```

Run this in another terminal:

```sh
mkdir -p backups
pg_dump \
  --format=custom \
  --blobs \
  --verbose \
  --file="backups/app-$(date -u +%Y%m%dT%H%M%SZ).dump"
```

## Dump All Databases

`pg_dumpall` is useful for roles and global objects, but it is not a substitute
for physical backups.

```sh
pg_dumpall \
  --verbose \
  --file="backups/all-$(date -u +%Y%m%dT%H%M%SZ).sql"
```

## Restore A Custom Dump

Restore into a clean database or a dedicated restore cluster first. Do not test
restore against the only production database.

```sh
export PGHOST="127.0.0.1"
export PGPORT="5432"
export PGDATABASE="app_restore"
export PGUSER="app"
export PGPASSWORD="<read-from-your-secret-manager>"

createdb "$PGDATABASE"

pg_restore \
  --dbname="$PGDATABASE" \
  --clean \
  --if-exists \
  --verbose \
  backups/app-YYYYMMDDTHHMMSSZ.dump
```

## Automating Logical Dumps

For automation, run the same commands from a CI job or Kubernetes CronJob that:

- reads database credentials from a Kubernetes Secret or external secret store;
- writes dumps to an encrypted object storage bucket;
- records dump size, duration and checksum;
- restores the latest dump in a non-production namespace on a schedule.

Physical backup restore and logical dump restore should both be tested before
running critical workloads.
