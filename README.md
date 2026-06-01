# NJ Personal Auto Loss-Ratio Pipeline — dbt (duckdb) + Airflow

Faithful migration of the two legacy T-SQL files (`PROCEDUREs.sql`,
`b.NJ LR DB.sql`) into a declarative dbt project that reads parquet and writes
parquet. The goal is **output parity** — the marts should reproduce the data the
legacy script produced, not a cleaned-up reinterpretation of it. Where the
legacy has a quirk or a bug, it is preserved on purpose and labelled.

## Architecture

```
MSSQL (RyanB + Claims)  --extract-->  parquet  --dbt(duckdb)-->  parquet marts
        connectorx                    /data            transform       /output
```

dbt is source-agnostic: it only reads the parquet you drop in `NJ_LR_PARQUET_DIR`.
You said you'll do the MSSQL download yourself — `extract/` is a working starting
point (connectorx, since the sources are SQL Server, not Postgres) but is
optional. Everything downstream of parquet is fully built here.

## Run it

```bash
pip install -r requirements.txt

# 1. land the parquet (your own method, or:)
cp extract/config.example.yml extract/config.yml          # edit table names
export NJ_LR_RYANB_CONN='mssql://user:pass@host:1433/XWei'
export NJ_LR_CLAIMS_CONN='mssql://user:pass@host:1433/CLAIMS_NJ'
export NJ_LR_PARQUET_DIR=./data
python extract/extract_mssql_to_parquet.py --config extract/config.yml

# 2. transform
cd dbt
cp profiles.yml.example profiles.yml                      # or ~/.dbt/profiles.yml
export DBT_PROFILES_DIR=$(pwd)
export NJ_LR_PARQUET_DIR=../data
export NJ_LR_OUTPUT_DIR=../output
dbt deps && dbt build
```

Marts land as parquet in `NJ_LR_OUTPUT_DIR`, browsable in any DuckDB session:

```sql
SELECT * FROM read_parquet('output/fct_freq_lr_by_accqtr.parquet') LIMIT 100;
```

## Legacy → dbt map

| Legacy (file2 lines) | What it did | dbt model |
|---|---|---|
| 1–23 | Quarter calendar | `int_quarters` |
| 31–109, 107–109 | Policy base + filters | `stg_pol_vehicle` |
| 116–132, 299–301 | END_DT cap + window delete | `int_policy_premium` |
| 150–166 | Full-term premium by coverage | `int_ft_premium` |
| 137–140 | BI limit text | `int_bi_desc` |
| 187–197 | Annualized premium + OTHER | `int_policy_premium` |
| 200–296 | On-level premium loop + UM/TOTAL collapse + pivot | `stg_pol_premium` → `int_onlevel_premium` |
| 303–308 | Earned exposure | `int_policy_premium` |
| 313–508 | All attribute CASE recodes + backfills | `int_policy_attributes` |
| 414–433, 418–426 | Claims source + filters + CVG map | `stg_claims_loss_reserve` |
| 445–460 | Claims feature aggregate + flags | `int_claims` |
| 464–609 | Exhibit 1 dimension/measure table | `int_freq_by_attributes` → `fct_freq_by_attributes` |
| 615–626 | Attach POL_PK + accident quarter to claims | `int_claims_polpk` |
| 634–688 | Policy × quarter explosion | `int_policy_month` |
| 691–731 | Per-coverage long premium/exposure | `int_accqtr_premium_long` (macro `unpivot_accqtr_premium`) |
| 737–756 | Claims rollup to POL_PK×CVG×QTR | `int_accqtr_claims_long` |
| 804–822 | Combine to AccQtr_attributes | `int_accqtr_combined` |
| 765–896 | Wide per-coverage pivot + dims | `fct_freq_lr_by_accqtr` (macro `pivot_by_coverage`) |
| File1 `NewTmpList`, `sp_AddNullColumns` | Runtime list/column builders | gone — replaced by Jinja loops + vars |

## What changed conceptually

The legacy is **imperative**: cursors, `WHILE` loops over coverages, dynamic
`EXEC`, and repeated `ALTER TABLE … ADD/DROP COLUMN … UPDATE` to mutate one wide
table in place. Three mechanical translations cover almost all of it:

1. **Loop over coverages → Jinja loop / `UNION ALL`.** The coverage list lives
   once in `dbt_project.yml` vars (`premium_sources`, `accqtr_coverages`,
   `premium_wide_coverages`). Add a coverage there, not in SQL.
2. **`UPDATE col` in place → a new derived column downstream.** Each legacy
   update becomes a CTE/column in the next model, so the data flows forward
   through a DAG instead of mutating.
3. **Dynamic DROP/ADD/UPDATE pivot → conditional aggregation.**
   `max(case when cvg='X' then measure end)` in `pivot_by_coverage`.

The 39.7M-row, 26-minute claims-attach join (legacy comment L759) is
`int_claims_polpk`. DuckDB does range joins far faster, but it's still the
heaviest step — that's why `profiles.yml.example` sets `memory_limit` and a
spill `temp_directory`.

---

## Validation status (what I actually ran)

`dbt build` was run end-to-end against **synthetic** parquet (tiny, internally
consistent rows for all 12 sources): **all 19 models execute in DuckDB and all
tests pass.** This confirms the SQL is dialect-correct (the `* exclude`, integer
`//`, date math, the range join, and both pivot macros all run) and the DAG
wires up. It does **NOT** confirm numeric parity with the legacy — that needs the
real data plus the original's output to diff against, which I don't have.

The synthetic run earned its keep: it caught a real bug. A multi-vehicle policy
whose vehicles had differing per-vehicle attributes made Exhibit 1 emit multiple
rows per `POL_PK`, which (a) broke the `POL_PK x YYYYQT` grain of Exhibit 2 and,
worse, (b) **double-counted claim losses** in the attach join — a silent
correctness bug that passed a naive check. The fix: Exhibit 1
(`int_freq_by_attributes`) is now one row per policy term with descriptive
attributes `MAX`-reduced (matching the legacy's own `MAX(BI)`/`MAX(UIM_STACK)`
pattern and the claims-attach join key). **This grain choice is the single most
important thing to confirm against your file** — see item 0 below.

## Finish list — what to confirm / wire before trusting the numbers

Nothing below blocks `dbt build`; the project compiles, runs, and passes tests on
synthetic data. These are the spots where faithful output depends on a detail I
could not fully verify from photos, or on a source outside these two files.

### 0. Exhibit 1 grain (highest priority — affects loss numbers)

The claims-attach join keys on `POL_NUM` + loss-date-in-window, which is only 1:1
if Exhibit 1 is one row per policy term. I reduced it to that grain with `MAX`
over descriptive attributes. Confirm against L536-602 / L765-822 that the legacy
does the same and does **not** split rows by a per-vehicle attribute (single/multi
car, BI limit, territory). If it does split, add that attribute to both the
`int_freq_by_attributes` group-by and the `fct_freq_lr_by_accqtr` pivot key — and
re-check that claims don't double-count.

### A. Spot-checks against the file (token-level, from darker frames)

These are exact-literal confirmations — the logic is built, just confirm the
strings:

1. **`int_ft_premium`** — the `CVG_CD IN (...)` member lists for PIP and UM, and
   the `NOT IN (...)` exclusion list for TOTAL (file2 ~L150-162). Long lists,
   easy to mis-read.
2. **`int_policy_attributes`** — `PRI_TENURE`: confirm the first literal is
   `'10000'` vs `'10,000'` (file2 ~L318).
3. **`stg_claims_loss_reserve`** — the `CO_CD IN (...)` company list (file2 ~L430).
4. **`int_claims_polpk`** — confirm L623 (`JOIN NJauto_freq_by_attributes`) is the
   live join and L622 (`JOIN tmp_NJfreq_pol`) is commented out. If reversed,
   point the join at `int_policy_attributes` instead.

### B. Group-by enumerations (plain attribute lists, no logic)

5. **`int_freq_by_attributes`** GROUP BY (file2 ~L536-602) and the dimension set
   carried into **`fct_freq_lr_by_accqtr`** (file2 ~L765-822). I captured these
   structurally; confirm exactly which recoded attributes are grouping keys and
   add/remove to match. There's a `>>> VERIFY` banner on the model.

### C. External sources (NOT in either file — must be wired)

6. **`valuation_date`** var (`dbt_project.yml`). Legacy derived the initial
   END_DT cap from `MAX(LSTDAY)` of a monthly calendar table `tmp_NJfreq_mon`
   that is built elsewhere and never appears in these files. Set this var to the
   as-of date the legacy run used (the quarter boundary just past your extract).
7. **External-source attribute columns** in `int_policy_attributes`, emitted as
   typed NULLs: `EXPCAT`, `MIN_EXP`, `MARKET`, `ISI`, `IA_AGENT_APPT_YR`,
   `GEOregion`, `PAY_Mapping`, `CLEAN_LVL`. Their populating tables aren't in
   these files. `EXPCAT` has its anchor row identified (`is_expcat_anchor`,
   lowest POL_PK per POL_NUM) — only the value mapping is missing.
8. **`UIM_STACK`** (`int_policy_attributes`). The recode is exact, but its input
   column is a `CONVERT(NULL)` placeholder with no populating step in either
   file. As written it resolves to `'No Coverage'` for everyone — faithful, but
   probably not intended. Wire `uim_stack_src` to the real source if one exists.

### D. Preserved legacy quirks (intentional — don't "fix" silently)

9. **`int_claims.close_cnt`** uses `COUNT(CASE WHEN … THEN 1 ELSE 0 END)`, which
   counts every row (the `ELSE 0` is non-null). So `CLOSE_CNT == FEATURE_CNT`
   always, which in turn drives `CWOP_CNT`. Reproduced exactly; the intended
   `SUM(...)` version is in a comment if you ever want it.
10. **On-level pivot loop bound** (legacy L276) iterated `COUNT(*) FROM CovList`
    (8) while reading a 7-element `TmpList`, harmlessly re-running the last
    coverage. Irrelevant once pivoted set-based — noted for completeness.

### E. Column completeness

11. **`stg_pol_vehicle`** selects the sourced columns I could read (~40). If a
    later model references a base column that isn't there, add it to staging —
    it'll be a genuine source column, not a derived one.

---

## Anything else worth flagging

- **There isn't one RyanB table — there are 11.** Beyond `Vehicle_DW`, the script
  reads `CVG_DW`, `VEHICLERAW`, and **eight** per-coverage `…_Premium_<cov>`
  tables. They're all enumerated in `models/sources.yml` and `extract/config`.
  Make sure your download produces all of them (the eight premium tables are the
  easiest to forget).
- **`TotPrem` vs `Total`.** The premium tables sum `TotPrem` except `TOTAL_VEH`,
  which sums `Total`. That mapping is the `premium_sources` var.
- **`LOSS` = incurred.** `int_accqtr_combined` uses incurred loss for the `LOSS_*`
  columns. If the exhibit you're matching reports paid loss, switch one line
  (commented in the model).
- **`YYYYQT` is `year*100 + quarter`** (e.g. `201903`), not a `yyyyQq` string.
  Both the calendar and the ACC_MO derivation use this; keep any dashboard
  filters consistent with it.
```
# test_dbtpipeline
