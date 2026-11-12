---
title: "Mirroring Bioconductor and building a DuckDB code index for AI models"
date: 2026-11-12
summary: >-
  Mirroring Bioconductor 3.23 and 3.24 source packages, indexing them with
  scip-r, and packaging the result as a DuckDB database an AI model can query.
authors:
  - admin
tags:
  - Bioconductor
  - DuckDB
  - scip-r
  - AI
draft: false
image:
  placement: 1
  focal_point: Center
  preview_only: false
---

The setup described here ran on a virtual machine on
[Jetstream2](https://jetstream-cloud.org/), referred to below as "this
instance". Nothing in it depends on Jetstream2: any cloud instance or local
machine with enough disk space will do.

This instance does two things. It keeps a local copy of Bioconductor's source
packages for release 3.23 and devel 3.24. It also runs
[scip-r](https://github.com/seandavi/scip-r), written by Sean Davis, over every
package, which produces an index of symbols, references and call relationships,
and packages that index as a DuckDB database that an AI model can query.

This post walks through how the mirror and index were set up, and how
`bioc-index.sh` turns the index into a database. The mirror steps follow the
[mirror
how-to](https://seandavi.github.io/bioc-infrastructure/mirror-how-to.html).
The scripts used here can be downloaded from the
[gist](https://gist.github.com/LiNk-NY/bc994fbd18f2f099157319995c36c9c5).

## Where things stand

As of 12 November 2026:

- **Source mirror**: `packages/3.23/bioc/src/contrib` (8.2 GB) and
  `packages/3.24/bioc/src/contrib` (6.9 GB), under
  `~/bioconductor_repositories`.
- **Index**: `out/` in each version directory, with a `parquet/` tree and a
  `bioc323.duckdb` or `bioc324.duckdb` view database.
- **Bundle**: `bioc324-index-20261104.tar.gz` (118.6 MB) with a `.sha256` file,
  built on 4 November 2026 from 3.24.

## Step 1: read the manifest

Each version and repository has a manifest listing every object, with its size
and MD5. Filter the `bioc` repository's manifest down to the source tarballs and
index files:

```sh
cd ~/bioconductor_repositories
curl -fsS https://bioconductor.org/api/v1/manifest/3.24/bioc.tsv.gz \
  | gunzip | cut -f1 | grep '/src/contrib/' > files-3-24.txt
```

The same command with `3.23` gives `files-3-23.txt`. The 3.23 list has 2,763
paths and the 3.24 list has 2,456.

## Step 2: copy with rclone

Copy the listed files with `rclone`:

```sh
rclone copy --http-url https://bioconductor.org :http: \
  ~/bioconductor_repositories --files-from files-3-24.txt --no-traverse
```

The how-to's `mirror-sync.sh` runs this copy and then recreates the symlinks.
This instance ran the copy by hand.

Paths in `--files-from` are relative to the destination, so each file lands
under `packages/<version>/bioc/src/contrib/`. Every path in both lists is
present on disk.

The list counts are higher than the tarball counts (2,763 against 2,758, and
2,456 against 2,451) because each list also includes non-tarball files. For 3.24
those are `PACKAGES`, `PACKAGES.gz`, `PACKAGES.rds` and two `Meta/*.rds` files.

## What this copy leaves out

- **Scope is source only.** The mirror has the `bioc` repository's `src/contrib`
  and nothing else: no `bin/`, no `data-annotation`, `data-experiment`,
  `workflows` or `books`. The how-to leaves that choice to you, and this
  instance picked source only.
- **No `release` or `devel` symlinks.** `packages/` contains only `3.23` and
  `3.24`. The how-to says URLs that go through those links return 404 without
  them. `mirror-sync.sh` recreates them; this copy did not.
- **The copy is a snapshot.** It dates from 4 November 2026. The manifest is
  regenerated hourly, and this user has no cron job, so nothing refreshes it.
  The how-to suggests a daily entry: `17 3 * * * DEST=/srv/bioc
  /usr/local/bin/mirror-sync.sh`.

## Step 3: build the index with scip-r

Install scip-r as a uv tool, as in its README:

```sh
uv tool install "scip-r[export] @ git+https://github.com/seandavi/scip-r"
```

For those interested, I submitted a feature request to scip-r as
[pull request #52](https://github.com/seandavi/scip-r/pull/52) to add
full function signatures in the index.

Run the batch in each version's `bioc` directory:

```sh
cd ~/bioconductor_repositories/packages/3.24/bioc
scip-r batch src/contrib -o out --jobs 14 --export parquet --hive
```

The `--resolve` flag records the installed R package versions. It needs R on
the machine, so add it only if R is installed (`sudo apt install r-base-core`
on Debian or Ubuntu). This index was built without it: none of the rows in
`out/summary.jsonl` has a `resolve_run_id`, so it is a static index.

The output is one directory per package under `out/`, a `summary.jsonl` with one
line per package, and `out/parquet/`, with one directory per table. `--hive`
partitions each table by `index_package` and `index_version`.

For 3.24, `summary.jsonl` has 2,451 rows, all with status `ok`. The index has
symbols for 2,431 packages. Six of the packages with no symbols are AHMassBank,
BiocVersion, alabaster.schemas, alabaster, assorthead and convert. Why the
other 14 have no symbols is not yet explained.

## Step 4: DuckDB views over the Parquet

Parquet is the store and DuckDB reads it through views. `~/make_duckdb.sh`
creates them:

```sh
~/make_duckdb.sh out out/bioc324.duckdb
```

Each view is a `read_parquet` over one table directory, for example:

```sql
CREATE OR REPLACE VIEW symbols AS
  SELECT * FROM read_parquet('/abs/path/out/parquet/symbols/**/*.parquet',
                             hive_partitioning=true);
```

The views store absolute paths, so the database copy in the bundle only works
on the machine that built it. Install rebuilds the views against the local
Parquet files.

The schema is described in scip-r's `docs/parquet-schema.md`. The six tables
are:

| Table | One row per |
|---|---|
| `metadata` | indexed package: tool version and provenance |
| `documents` | source file |
| `symbols` | symbol defined in a document |
| `external_symbols` | symbol referenced but defined in another package |
| `occurrences` | reference or definition site, with its enclosing `caller` |
| `relationships` | S3/S4 method to its generic, or class to its superclass |

For 3.24 the database holds 12,307,301 occurrences, 338,790 external symbols,
36,721 documents and 27,175 relationships.

## Step 5: bundle on the VM

`bioc-index.sh` is in the working directory. Bundle 3.24 from there:

```sh
cd ~/bioconductor_repositories
./bioc-index.sh bundle 3.24
```

The script takes `3.24` and works out the names: the tag is `bioc324` and the
bundle is `bioc324-index-<date>.tar.gz`. Its default source is
`packages/3.24/bioc/out`, and it writes into the current directory. The bundle
contains `parquet/` and `bioc324.duckdb`. The database is included for reference
only, because install rebuilds it. The script also writes a `.sha256` file next
to the tarball.

## Step 6: install where the model runs

Copy the tarball and its `.sha256` to the machine that will serve the index.
There, run:

```sh
./bioc-index.sh install bioc324-index-20261104.tar.gz
```

The install verifies the checksum, checks that the `duckdb` CLI is on the path,
extracts the bundle into `~/bioc-index/<bundle name>` unless you pass a
destination, and recreates the views against the local Parquet files. It then
prints package and symbol counts. The output below is from the Jetstream2 VM,
where the default user is `exouser`. On your own machine, `~/bioc-index` is
under your home directory instead:

```
bioc324-index-20261104.tar.gz: OK
Installed to /home/exouser/bioc-index/bioc324-index-20261104
│     2431 │  191331 │
Database: /home/exouser/bioc-index/bioc324-index-20261104/bioc324.duckdb
```

That is 305 MB on disk, and it took about six seconds.

If you use the snap-packaged `duckdb`, pass a destination under `$HOME`,
because the snap cannot see `/tmp`.

## Step 7: query it

The queries in this step show what the index can answer, and they are useful
for checking that the install worked. In day-to-day use you would not write
them yourself. The AI model writes and runs them, as described in the next
section. Each query below is paired with a prompt you might give the model to
get it.

Open the database read-only:

```sh
duckdb -readonly ~/bioc-index/bioc324-index-20261104/bioc324.duckdb
```

The packages with the most function symbols:

> Which five Bioconductor packages define the most functions?

```sql
SELECT index_package, count(*) AS n_symbols
FROM symbols WHERE is_function
GROUP BY 1 ORDER BY 2 DESC LIMIT 5;
```

This returns ChemmineOB (4,566), mia (1,392), igblastr (1,353), xcms (1,235) and
S4Vectors (1,049).

A call graph for limma, using the `GROUP BY caller, symbol` pattern from the
schema doc:

> In limma, which functions call which other functions most often?

```sql
SELECT caller, symbol, count(*) AS n
FROM occurrences
WHERE caller IS NOT NULL AND NOT is_definition AND index_package = 'limma'
GROUP BY ALL ORDER BY n DESC LIMIT 4;
```

The top rows show `printtipWeights()` calling `base::sum()` 136 times. The
`caller` and `symbol` columns hold raw SCIP strings such as `scip-r . base .
sum().`, and `local N` marks a file-local symbol. For a clean function-level
graph, add `AND NOT is_local` and use the parsed `package` and `name` columns
instead of splitting the strings.

Counting how often each function from another package is called:

> Across Bioconductor, which functions from other packages are called most
> often, and by how many packages?

```sql
SELECT package, name, count(*) AS calls,
       count(DISTINCT index_package) AS n_pkgs
FROM occurrences
WHERE NOT is_local AND NOT is_definition AND is_function
  AND package <> index_package
GROUP BY ALL ORDER BY calls DESC LIMIT 10;
```

Including base R, `base::c` leads with 238,725 calls from 2,376 packages,
followed by `base::length` and `base::return`. Excluding base R, which
you can do by adding `AND package NOT IN ('base', 'methods', 'stats',
'utils', 'grid', 'graphics', 'grDevices', 'tools', 'parallel')` (and the
other base packages) to the `WHERE` clause, `ggplot2::aes` leads with 5,794
calls from 465 packages, followed by `dplyr::mutate` and `dplyr::filter`. The
prompt for that version:

> Same question, but leave out base R packages.

Two things to know about these counts:

- `return` is a function call in R, so it ranks high. Drop it if you only
  want library functions.
- Ranking by `n_pkgs` instead of `calls` finds functions that many packages
  share, rather than functions that one package calls heavily.

## Giving it to a model

A reasonable setup gives the model two things: the scip-r schema doc, and one
tool that runs read-only SQL against the database. With the schema doc in
context, the model can write its own queries. That tool isn't built yet, and it
is the next step.

## Things to change next time

1. Use `mirror-sync.sh`, or make the `release` and `devel` symlinks by hand, so
   URLs through those names work.
2. Schedule the sync. The copy dates from 4 November 2026, and the
   manifest is regenerated every hour.
3. Install under `$HOME` when you use the snap `duckdb`.
4. Decide whether the index covers source only, as it does here, or the binaries
   too.
5. `bioc-index.sh` hard-codes `SRC_ROOT` to
   `/home/exouser/bioconductor_repositories/packages`, the path on the
   Jetstream2 VM. On another machine, or as a user other than `exouser`, either
   edit `SRC_ROOT` or pass the index directory as the second argument:
   `./bioc-index.sh bundle 3.24 ~/bioconductor_repositories/packages/3.24/bioc/out`.
