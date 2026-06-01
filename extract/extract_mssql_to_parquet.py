"""
Extract MSSQL (RyanB warehouse + linked Claims server) -> parquet.

This is the piece that sits in front of dbt. dbt then reads the parquet, so the
transform layer is source-agnostic. You said you'll handle the download yourself
either way — this is a working starting point you can keep or replace.

Why connectorx (not the postgres-to-parquet repo): the sources are SQL Server,
and connectorx speaks the SQL Server / TDS dialect and streams straight into
Arrow, so large tables don't have to fit in pandas memory.

Usage
-----
    pip install connectorx pyarrow pyyaml
    export NJ_LR_RYANB_CONN='mssql://user:pass@host:1433/XWei'
    export NJ_LR_CLAIMS_CONN='mssql://user:pass@host:1433/CLAIMS_NJ'
    export NJ_LR_PARQUET_DIR=./data
    python extract_mssql_to_parquet.py --config config.yml
    # or a subset:
    python extract_mssql_to_parquet.py --config config.yml --only pol_vehicle premium_bi

Notes
-----
* connectorx connection string format for SQL Server:
      mssql://<user>:<pass>@<host>:<port>/<database>
  (it uses the TDS protocol; no ODBC DSN needed). For Windows auth or ODBC,
  swap to a pyodbc-based reader — the write_parquet() helper stays the same.
"""

import argparse
import os
import sys
from pathlib import Path

import yaml

try:
    import connectorx as cx
except ImportError:
    cx = None


def resolve(name_template: str, prefix: str) -> str:
    return name_template.replace("{prefix}", prefix)


def query_for(spec: str, prefix: str) -> str:
    """A spec is either a bare table name (-> SELECT *) or a full SQL query."""
    s = resolve(spec, prefix).strip()
    if s.lower().startswith("select"):
        return s
    return f"SELECT * FROM {s}"


def extract_one(name: str, query: str, conn: str, out_dir: Path) -> None:
    out_path = out_dir / f"{name}.parquet"
    print(f"[extract] {name:18s} -> {out_path}")
    if cx is None:
        raise RuntimeError("connectorx not installed: pip install connectorx pyarrow")
    # return_type='arrow' streams into an Arrow table; write with pyarrow.
    table = cx.read_sql(conn, query, return_type="arrow")
    import pyarrow.parquet as pq
    pq.write_table(table, out_path)
    print(f"[extract] {name:18s} done ({table.num_rows:,} rows)")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="config.yml")
    ap.add_argument("--only", nargs="*", help="extract only these logical names")
    args = ap.parse_args()

    cfg = yaml.safe_load(Path(args.config).read_text())
    prefix = cfg.get("prefix", "")
    out_dir = Path(os.environ.get("NJ_LR_PARQUET_DIR", "data"))
    out_dir.mkdir(parents=True, exist_ok=True)

    jobs = []
    for group in ("ryanb", "claims"):
        gcfg = cfg.get(group, {})
        conn = os.environ.get(gcfg.get("conn_env", ""), "")
        for name, spec in gcfg.get("tables", {}).items():
            if args.only and name not in args.only:
                continue
            if not conn:
                print(f"[warn] {name}: env {gcfg.get('conn_env')} not set; skipping")
                continue
            jobs.append((name, query_for(spec, prefix), conn))

    if not jobs:
        print("[warn] nothing to extract (check --only and connection env vars)")
        return 1

    for name, query, conn in jobs:
        extract_one(name, query, conn, out_dir)

    print(f"[done] {len(jobs)} table(s) -> {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
