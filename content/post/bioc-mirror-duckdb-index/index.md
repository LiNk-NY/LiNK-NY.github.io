---
title: "Mirroring Bioconductor and Building a DuckDB Code Index for AI Models"
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

When working with Large Language Models (LLMs) on bioinformatics software tasks,
grounding models with precise code intelligence is essential to avoid
hallucinations of package functions, parameters, and class structures.

This post walks through how to mirror Bioconductor source packages, index them
with [scip-r](https://github.com/seandavi/scip-r) (developed by Sean Davis), and
package the result into a lightweight, queryable DuckDB database designed for AI
models and developer tooling.[^claude]

The pipeline accomplishes two main tasks:
1. **Mirroring**: Maintains a local copy of Bioconductor source packages for
   current release (3.23) and devel (3.24).
2. **Indexing and packaging**: Runs `scip-r` across every package to index
   symbols, references, and call relationships, stores the output in Parquet
   format, and exposes it via a DuckDB database that an AI agent can query.

The setup ran on a virtual machine on
[Jetstream2](https://jetstream-cloud.org/), though any local machine or cloud
instance with sufficient disk space will work. The mirroring steps adapt Sean
Davis's [Bioconductor mirror
how-to](https://seandavi.github.io/bioc-infrastructure/mirror-how-to.html), and
helper scripts used throughout this guide are available in this [GitHub
Gist](https://gist.github.com/LiNk-NY/bc994fbd18f2f099157319995c36c9c5).

## Where things stand

As of 12 November 2026, here is the current state of the mirror, index, and
distribution bundle:

- **Source mirror**: `packages/3.23/bioc/src/contrib` (8.2 GB) and
  `packages/3.24/bioc/src/contrib` (6.9 GB), located under
  `~/bioconductor_repositories`.
- **Index**: An `out/` directory for each Bioconductor version containing a
  Hive-partitioned `parquet/` tree and a corresponding `bioc323.duckdb` or
  `bioc324.duckdb` database view file.
- **Bundle**: A portable tarball `bioc324-index-20261104.tar.gz` (118.6 MB
  compressed) with an accompanying `.sha256` checksum, built from version 3.24.

## Step 1: Read the manifest

Bioconductor publishes an API manifest for each version and repository listing
every object along with its size and MD5 hash. We can download and filter the
`bioc` software repository's manifest down to just the source tarballs and
package repository index files:

```sh
cd ~/bioconductor_repositories
curl -fsS https://bioconductor.org/api/v1/manifest/3.24/bioc.tsv.gz \
  | gunzip | cut -f1 | grep '/src/contrib/' > files-3-24.txt
```

Running the same command for `3.23` generates `files-3-23.txt`. The 3.23
manifest contains 2,763 paths, while the 3.24 manifest contains 2,456.

## Step 2: Copy with rclone

Using `rclone`, copy the listed files directly from Bioconductor:

```sh
rclone copy --http-url https://bioconductor.org :http: \
  ~/bioconductor_repositories --files-from files-3-24.txt --no-traverse
```

Because paths in `--files-from` are relative to the destination root, each
package lands cleanly in `packages/<version>/bioc/src/contrib/`. Every path in
both lists is present on disk.

A couple of details to note:
- **Total file counts vs. package tarballs:** The manifest lists contain
  slightly more entries than actual package tarballs (2,763 vs. 2,758 for 3.23,
  and 2,456 vs. 2,451 for 3.24). The extra files are repository index metadata:
  `PACKAGES`, `PACKAGES.gz`, `PACKAGES.rds`, and two files under `Meta/`.
- **Automation:** The how-to guide provides a `mirror-sync.sh` script (included
  in the gist) that automates this download and manages symlinks. For this
  initial build, I executed the copy command directly.

## What this copy leaves out

To keep the footprint focused and manageable, this mirror intentionally omits
certain elements:

- **Source packages only:** The mirror captures only the `bioc` software
  repository's `src/contrib` directory. It skips precompiled binaries (`bin/`),
  as well as annotation (`data-annotation`), experiment (`data-experiment`),
  workflow (`workflows`), and book (`books`) repositories. Since the primary
  goal is source code intelligence, source packages are all we need.
- **No `release` or `devel` symlinks:** The `packages/` directory contains only
  explicit version numbers (`3.23` and `3.24`). Downstream tools expecting
  canonical `release` or `devel` URLs will return a 404 without these symlinks.
  The `mirror-sync.sh` script recreates them automatically, but they were
  skipped for this manual snapshot.
- **Point-in-time snapshot:** This copy is a static snapshot from 4
  November 2026. While upstream Bioconductor manifests regenerate hourly, no
  recurring cron job is scheduled here yet. For a production mirror, Sean's
  guide suggests a daily cron entry:
  ```cron
  17 3 * * * DEST=/srv/bioc /usr/local/bin/mirror-sync.sh
  ```

## Step 3: Build the index with scip-r

[scip-r](https://github.com/seandavi/scip-r) generates Code Intelligence
Protocol (SCIP) indexes for R code, extracting definitions, references, and
symbol relationships.

First, install `scip-r` using `uv`:

```sh
uv tool install "scip-r[export] @ git+https://github.com/seandavi/scip-r"
```

> [!NOTE]
> For those interested, I submitted
> [pull request #52](https://github.com/seandavi/scip-r/pull/52) to
> `scip-r` to add full function signatures to the index.

Next, run the batch indexer inside each version's `bioc` directory:

```sh
cd ~/bioconductor_repositories/packages/3.24/bioc
scip-r batch src/contrib -o out --jobs 14 --export parquet --hive
```

Key arguments:
- `--jobs 14`: Runs indexing across 14 parallel worker processes (adjust
  according to your VM's available CPU cores).
- `--export parquet --hive`: Exports SCIP data into Parquet tables partitioned
  in Hive style by `index_package` and `index_version`.
- `--resolve` (omitted): This flag resolves symbol definitions against installed
  R packages, requiring an R installation on the system (`sudo apt install
  r-base-core`). This index was built without `--resolve`, yielding a purely
  static source code index (no `resolve_run_id` entries in `summary.jsonl`).

### Output structure and coverage

The batch run produces:
- One subfolder per package under `out/`
- A summary log at `out/summary.jsonl`
- Partitioned Parquet tables under `out/parquet/`

For Bioconductor 3.24, `summary.jsonl` contains 2,451 entries, all reporting
`ok` status. Of those, 2,431 packages produced indexed symbols.

The 20 packages without symbols include:
- Metadata or schema packages that contain no R function definitions (e.g.,
  `AHMassBank`, `BiocVersion`, `alabaster.schemas`, `alabaster`, `assorthead`,
  `convert`).
- 14 additional packages currently being inspected (typically data-only packages
  or packages with non-standard structures).

## Step 4: DuckDB views over Parquet

Instead of duplicating data into a bulky database file, Parquet acts as our
storage engine while DuckDB provides a fast, zero-copy query interface via
views.

We generate the views using `~/make_duckdb.sh` (available in the gist):

```sh
~/make_duckdb.sh out out/bioc324.duckdb
```

Under the hood, the script creates a view for each Parquet table directory:

```sql
CREATE OR REPLACE VIEW symbols AS
  SELECT * FROM read_parquet('/abs/path/out/parquet/symbols/**/*.parquet',
                             hive_partitioning = true);
```

> [!IMPORTANT]
> Because DuckDB views store absolute file paths, a database created on the
> build machine cannot be copied as-is to another machine with a different
> filesystem layout. As detailed in Step 6, our installation script
> automatically regenerates these views locally.

### Database schema

The schema follows `scip-r`'s Parquet specification (`docs/parquet-schema.md`):

| Table | One row per |
|---|---|
| `metadata` | Indexed package metadata, tool version, and provenance |
| `documents` | Source file within a package |
| `symbols` | Symbol defined within a document |
| `external_symbols` | External symbol referenced by, but defined outside of, the package |
| `occurrences` | Code occurrence (reference or definition site) along with its enclosing `caller` |
| `relationships` | Method-to-generic (S3/S4) or class inheritance (superclass) relationship |

For Bioconductor 3.24, this yields **12,307,301 occurrences**, **338,790
external symbols**, **36,721 documents**, and **27,175 relationships**.

## Step 5: Bundle on the build machine

To easily distribute the index to local workstations or agent environments, we
use `bioc-index.sh` (from the gist):

```sh
cd ~/bioconductor_repositories
./bioc-index.sh bundle 3.24
```

The script:
1. Infers the tag (`bioc324`) and bundle name (`bioc324-index-YYYYMMDD.tar.gz`).
2. Collects `out/parquet/` (and includes `bioc324.duckdb` for reference).
3. Compresses the archive (reducing ~305 MB of Parquet data to just ~118 MB).
4. Generates a `.sha256` checksum file alongside the tarball.

## Step 6: Install where the model runs

Transfer the tarball and `.sha256` file to your target workstation or AI host
machine, then run:

```sh
./bioc-index.sh install bioc324-index-20261104.tar.gz
```

The `install` command handles setup end-to-end:
1. Verifies the SHA-256 checksum.
2. Confirms that the `duckdb` CLI is installed and in your `PATH`.
3. Extracts the archive to `~/bioc-index/<bundle-name>` (or a custom path passed
   as a second argument).
4. Rebuilds the DuckDB views using local absolute paths.
5. Runs a quick verification query reporting package and symbol counts.

Example output from the VM:

```
bioc324-index-20261104.tar.gz: OK
Installed to /home/exouser/bioc-index/bioc324-index-20261104
│ packages │ symbols │
├──────────┼─────────┤
│     2431 │  191331 │
Database: /home/exouser/bioc-index/bioc324-index-20261104/bioc324.duckdb
```

The installed index occupies only ~305 MB on disk, and unpacking and view
generation takes about six seconds.

> [!TIP]
> If you installed DuckDB via Snap (`snap install duckdb`), ensure you specify
> an installation directory inside `$HOME`, as snap confinement prevents DuckDB
> from accessing `/tmp`.

## Step 7: Query the index

These example queries illustrate the types of questions the index can answer.
While you can run them directly in the DuckDB CLI, the primary goal is enabling
an AI agent to execute them dynamically during bioinformatics reasoning. Each
query below is shown alongside the natural language prompt that might prompt an
LLM to generate it.

Start the DuckDB shell in read-only mode:

```sh
duckdb -readonly ~/bioc-index/bioc324-index-20261104/bioc324.duckdb
```

### Example 1: Packages defining the most functions

> **Prompt:** Which five Bioconductor packages define the most functions?

```sql
SELECT index_package, count(*) AS n_symbols
FROM symbols
WHERE is_function
GROUP BY 1
ORDER BY 2 DESC
LIMIT 5;
```

**Results:** ChemmineOB (4,566), mia (1,392), igblastr (1,353), xcms (1,235),
and S4Vectors (1,049).

---

### Example 2: Intra-package call graph

> **Prompt:** In `limma`, which functions call which other functions most often?

```sql
SELECT caller, symbol, count(*) AS n
FROM occurrences
WHERE caller IS NOT NULL
  AND NOT is_definition
  AND index_package = 'limma'
GROUP BY ALL
ORDER BY n DESC
LIMIT 4;
```

**Results:** In `limma`, `printtipWeights()` calling `base::sum()` tops the list
with 136 invocations.

The `caller` and `symbol` columns store raw SCIP identifiers (such as `scip-r .
base . sum().`), while file-local symbols are designated by `local N`. For
cleaner function-level graphs, filter with `AND NOT is_local` and use the
pre-parsed `package` and `name` columns.

---

### Example 3: Cross-package dependency and usage counts

> **Prompt:** Across all of Bioconductor, which external functions from other
> packages are called most often, and by how many packages?

```sql
SELECT package, name, count(*) AS calls,
       count(DISTINCT index_package) AS n_pkgs
FROM occurrences
WHERE NOT is_local
  AND NOT is_definition
  AND is_function
  AND package <> index_package
GROUP BY ALL
ORDER BY calls DESC
LIMIT 10;
```

**Results:**
- **Including base R:** `base::c` leads overwhelmingly with 238,725 calls across
  2,376 packages, followed by `base::length` and `base::return`.
- **Excluding base R:** Filtering out base packages (`AND package NOT IN
  ('base', 'methods', 'stats', 'utils', 'grid', 'graphics', 'grDevices',
  'tools', 'parallel')`) reveals that `ggplot2::aes` leads with 5,794 calls
  across 465 packages, followed closely by `dplyr::mutate` and `dplyr::filter`.

> [!NOTE]
> - `return` is a function call in R syntax, which is why it ranks prominently
>   unless explicitly filtered.
> - Ordering by `n_pkgs` rather than raw `calls` highlights functions with
>   widespread adoption across the ecosystem, whereas ordering by `calls`
>   highlights functions that are heavily looped or repeated in specific
>   codebases.

## Giving it to an AI model

Connecting an LLM or AI agent to this index requires two straightforward
components:
1. **Schema context:** Provide the `scip-r` schema definition in the agent's
   system prompt or tool definition so the model understands the available
   tables, columns, and relationships.
2. **SQL query tool:** Expose a read-only DuckDB execution tool (e.g., via a
   Model Context Protocol (MCP) server or standard agent tool call). Because
   DuckDB executes locally and finishes in milliseconds, the model can
   iteratively explore symbols, trace function callers, and inspect class
   hierarchies without hallucinating APIs.

## Lessons learned and future improvements

Reflecting on the setup, several refinements could streamline future iterations:

1. **Automate mirroring with symlinks:** Use `mirror-sync.sh` directly (or
   manually create `release` and `devel` symlinks) so standard package URLs work
   seamlessly through the mirror.
2. **Schedule periodic synchronization:** The mirror is currently a
   point-in-time snapshot. Adding a recurring cron job for `mirror-sync.sh` will
   keep packages in sync with upstream hourly manifest updates.
3. **Handle Snap permissions:** When using a snap-installed `duckdb`, always
   choose an installation path under `$HOME` to comply with confinement rules.
4. **Evaluate binary package indexing:** Consider whether to index binary
   repositories in addition to source tarballs.
5. **Parameterize source paths:** `bioc-index.sh` defaults `SRC_ROOT` to
   `/home/exouser/bioconductor_repositories/packages`. On other systems or under
   different usernames, remember to update `SRC_ROOT` or pass the path
   explicitly:
   ```sh
   ./bioc-index.sh bundle 3.24 ~/bioconductor_repositories/packages/3.24/bioc/out
   ```

[^claude]: This post was prepared by Claude Opus 5.5 (model ID
    `claude-opus-5-5`), an AI model made by Anthropic, using Claude Code.
