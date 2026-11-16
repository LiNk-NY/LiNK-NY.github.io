---
title: "CPTACdata: Adding CPTAC Proteomics to TCGA MultiAssayExperiments"
date: 2026-11-16
summary: >-
  CPTACdata downloads mass-spectrometry proteomics from the Proteomic Data
  Commons and appends it to curatedTCGAData objects, so protein, RNA and DNA
  measurements from the same TCGA patients sit in one MultiAssayExperiment.
authors:
  - admin
tags:
  - Bioconductor
  - CPTAC
  - TCGA
  - Proteomics
  - MultiAssayExperiment
draft: false
image:
  caption: "Overlap of TCGA ovarian patients across RPPA and CPTAC proteome and phosphoproteome data"
  placement: 1
  focal_point: Center
  preview_only: false
---

The Cancer Genome Atlas (TCGA) gave us the genome, epigenome and transcriptome
of thousands of tumors. What it measured only sparsely is the protein layer:
TCGA's reverse-phase protein arrays (RPPA) cover around 200 antibody targets.
Protein abundance often departs from mRNA abundance, so for many questions,
such as whether a copy-number gain actually raises the protein level or which
kinases are active, you need the proteins themselves.

The Clinical Proteomic Tumor Analysis Consortium (CPTAC) filled part of that
gap. It ran deep mass-spectrometry proteomics and phosphoproteomics on
hundreds of TCGA breast and ovarian tumors, measuring thousands of proteins
and tens of thousands of phosphosites per sample. Those data live in the
[Proteomic Data Commons](https://pdc.cancer.gov/) (PDC), under CPTAC case and
aliquot identifiers, separate from the TCGA data most of us already work with.

[CPTACdata](https://github.com/LiNk-NY/CPTACdata) is a new R package that joins
the two.[^claude] It queries the PDC, matches CPTAC samples to TCGA barcodes,
and adds the proteomics as new experiments in a `MultiAssayExperiment` from
[curatedTCGAData](https://bioconductor.org/packages/curatedTCGAData). The
protein data then line up with the mutation, copy-number, RNA-seq and
methylation assays of the same patients, with no identifier wrangling on your
part.

## What you get

- **`appendCPTAC()`** adds CPTAC proteome, phosphoproteome (and, where the PDC
  provides a matrix, glycoproteome) data to a TCGA `MultiAssayExperiment`.
- **`getCPTAC()`** downloads the CPTAC-3 and CPTAC-2 Prospective cohorts, which
  have their own patients rather than TCGA ones, as new
  `MultiAssayExperiment` objects with the PDC clinical data as `colData`.
- **`cptacProjects`** and **`cptacCohorts`** are tables shipped with the
  package that list which PDC studies are available, so you can see what
  exists before touching the network.

## Installation

CPTACdata is under review for Bioconductor. Until it is accepted, install it
from GitHub:

```r
if (!requireNamespace("BiocManager", quietly = TRUE))
    install.packages("BiocManager")

BiocManager::install("LiNk-NY/CPTACdata")
```

## Which TCGA tumors have CPTAC data?

`cptacProjects` has one row per TCGA project and PDC study:

```r
library(CPTACdata)
data("cptacProjects", package = "CPTACdata")
cptacProjects[, c("tcga_project", "experiment", "data_type")]
#>   tcga_project                 experiment  data_type
#> 1    TCGA-BRCA             CPTAC_Proteome log2_ratio
#> 2    TCGA-BRCA      CPTAC_Phosphoproteome log2_ratio
#> 3    TCGA-COAD             CPTAC_Proteome       <NA>
#> 4    TCGA-READ             CPTAC_Proteome       <NA>
#> 5      TCGA-OV    CPTAC_JHU_Glycoproteome       <NA>
#> 6      TCGA-OV         CPTAC_JHU_Proteome log2_ratio
#> 7      TCGA-OV        CPTAC_PNNL_Proteome log2_ratio
#> 8      TCGA-OV CPTAC_PNNL_Phosphoproteome log2_ratio
```

Breast (BRCA) and ovarian (OV) tumors have downloadable proteome and
phosphoproteome matrices. The colorectal (COAD/READ) proteome and the ovarian
glycoproteome have biospecimen records in the PDC, but its API currently
returns no quantification matrix for them (`data_type = NA`), so
`appendCPTAC()` skips them with a warning.

## A worked example: TCGA ovarian cancer

The CPTAC data are provided under the [PDC Data Use
Agreement](https://proteomic.datacommons.cancer.gov/pdc/data-use-guidelines).
Read it, then accept it for your session:

```r
options(CPTACdata.acceptDUA = TRUE)
```

Start from any `curatedTCGAData` object for a single TCGA project. Here we use
the ovarian RPPA data:

```r
library(curatedTCGAData)
library(MultiAssayExperiment)

mae <- curatedTCGAData("OV", "RPPAArray", version = "2.1.1", dry.run = FALSE)
```

Before downloading any matrices, a dry run reports how many of your patients
each PDC study covers:

```r
appendCPTAC(mae, dry_run = TRUE)
#>            experiment pdc_study_id quant_available mae_patients pdc_patients
#> 1  CPTAC_JHU_Proteome    PDC000113            TRUE          420          122
#> 2 CPTAC_PNNL_Proteome    PDC000114            TRUE          420           84
#>   matched_patients
#> 1              119
#> 2               81
```

Then append. The TCGA project is detected from the `colData`, and the proteome
is added by default. Call `appendCPTAC()` again for the phosphoproteome:

```r
mae <- appendCPTAC(mae)
#> Adding CPTAC_JHU_Proteome from PDC000113 (119 patients)...
#> Adding CPTAC_PNNL_Proteome from PDC000114 (81 patients)...
mae <- appendCPTAC(mae, fraction = "Phosphoproteome")
#> Adding CPTAC_PNNL_Phosphoproteome from PDC000115 (66 patients)...
mae
#> A MultiAssayExperiment object of 4 listed
#>  experiments with user-defined names and respective classes.
#>  Containing an ExperimentList class object of length 4:
#>  [1] OV_RPPAArray-20160128: SummarizedExperiment with 208 rows and 427 columns
#>  [2] CPTAC_JHU_Proteome: SummarizedExperiment with 8597 rows and 119 columns
#>  [3] CPTAC_PNNL_Proteome: SummarizedExperiment with 7480 rows and 81 columns
#>  [4] CPTAC_PNNL_Phosphoproteome: SummarizedExperiment with 21478 rows and 66 columns
```

The 208 RPPA targets are now joined by roughly 8,600 proteins and 21,000
phosphosites. Each new experiment is a `SummarizedExperiment` whose columns
are TCGA sample barcodes, and the `sampleMap` links them to the same patients
as every other assay. The figure at the top of this post, from
`upsetSamples(mae)`, shows how many patients each combination of the RPPA,
JHU proteome, PNNL proteome and PNNL phosphoproteome experiments shares.

Because everything is in one `MultiAssayExperiment`, the usual tools apply.
For example, to keep only patients with both RPPA and PNNL proteome data and
compare the two platforms:

```r
both <- intersectColumns(
    mae[, , c("OV_RPPAArray-20160128", "CPTAC_PNNL_Proteome")]
)
longFormat(both)
```

Adding RNA-seq, copy number or mutations is just a matter of requesting those
assays from `curatedTCGAData` before calling `appendCPTAC()`.

## Things worth knowing about the data

- **Units.** The proteome and phosphoproteome assays are `log2_ratio`: the log2
  ratio of each sample's abundance to a common reference the PDC used for the
  whole study. 0 means the same abundance as the reference, 1 means twice, -1
  means half. The reference is set per study, so compare values across
  experiments (e.g. JHU vs. PNNL) with care.
- **Rows.** Proteome rows are gene symbols. Phosphoproteome rows are RefSeq
  protein and site identifiers, such as `NP_000005.2:s710`.
- **Replicates.** Technical replicates carry a `.1`, `.2` suffix and are all
  kept by default; `replicates = "first"` keeps one per sample. The
  `sample_submitter_id` column of `colData` gives the shared sample barcode.
- **Provenance.** Each experiment's `metadata()` records the PDC study ID,
  study version, UUID, download time and CPTACdata version, so you can tell
  later exactly which data an analysis used.
- **Caching.** Biospecimen tables are cached for the R session, so a dry run
  followed by an append downloads each one only once.

## Beyond TCGA: the CPTAC cohorts

Most CPTAC data come from cohorts with their own patients: the CPTAC-3
discovery and confirmatory studies (clear cell renal cell carcinoma,
glioblastoma, lung adenocarcinoma and squamous cell carcinoma, head and neck,
pancreatic, uterine, melanoma, AML and others) and the CPTAC-2 Prospective
breast, colon and ovarian collections. Besides proteome and phosphoproteome,
many include acetylome, ubiquitylome and glycoproteome studies.

`getCPTAC()` downloads one cohort as a `MultiAssayExperiment`, with one
experiment per PDC study and the PDC clinical data as `colData`:

```r
data("cptacCohorts", package = "CPTACdata")
unique(cptacCohorts[["cohort"]])

getCPTAC("CPTAC CCRCC Discovery Study", dry_run = TRUE)
ccrcc <- getCPTAC("CPTAC CCRCC Discovery Study", experiments = "Proteome")
```

Tumor and normal samples from the same patient share one row of the
`colData`, which makes paired tumor-normal comparisons straightforward. See
`vignette("CPTACcohorts", package = "CPTACdata")` for a full walkthrough.

## How it compares

[cBioPortalData](https://bioconductor.org/packages/cBioPortalData) also
returns cancer studies as `MultiAssayExperiment` objects and includes the
TCGA RPPA data, and some cBioPortal studies carry CPTAC-derived protein
tables. CPTACdata reads the mass-spectrometry quantifications directly from
the PDC, keeps PDC identifiers and study versions alongside the data, and
plugs into `curatedTCGAData` objects you may already be using. Check which
source has the studies you need before choosing.

## What's next

Once CPTACdata is accepted into Bioconductor, I intend to integrate its
functionality into `curatedTCGAData`. The goal is to make CPTAC proteomics
available alongside the other TCGA assays when you build a
`MultiAssayExperiment`, so you no longer need a separate `appendCPTAC()` step.

## Try it and tell me what breaks

If you work with TCGA breast or ovarian tumors, CPTACdata gives you a matched
protein layer in a few lines of code. Bug reports and feature requests are
welcome on the [GitHub issue
tracker](https://github.com/LiNk-NY/CPTACdata/issues), especially if a PDC
study you need is missing or a matrix fails to download.

[^claude]: This post was prepared by Claude Opus 5.5 (model ID
    `claude-opus-5-5`), an AI model made by Anthropic, using Claude Code.
