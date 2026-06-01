"""
NJ Personal Auto loss-ratio pipeline — Airflow orchestration.

Coarse-grained on purpose: Airflow coordinates the two boundaries dbt can't see
(pulling MSSQL -> parquet) and then hands the whole transform to dbt as one
build. dbt resolves its own internal model order via ref(), so there is no value
in re-expressing every model as an Airflow task here.

  extract_ryanb  ┐
                 ├─> dbt_deps ─> dbt_build ─> dbt_test
  extract_claims ┘

If you want per-model tasks, retries, and lineage inside Airflow, swap the
BashOperator dbt step for astronomer-cosmos (DbtTaskGroup) — noted below.
"""

from datetime import datetime, timedelta
from pathlib import Path
import os

from airflow import DAG
from airflow.operators.bash import BashOperator

PROJECT_ROOT = Path(os.environ.get("NJ_LR_PROJECT_ROOT", "/opt/nj_lr_dbt"))
EXTRACT_DIR = PROJECT_ROOT / "extract"
DBT_DIR = PROJECT_ROOT / "dbt"

default_args = {
    "owner": "actuarial-data",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    dag_id="nj_lr_pipeline",
    description="NJ PA loss-ratio: MSSQL -> parquet -> dbt(duckdb) -> parquet marts",
    default_args=default_args,
    schedule="@monthly",          # quarterly data; monthly catches the boundary
    start_date=datetime(2025, 1, 1),
    catchup=False,
    tags=["nj", "loss-ratio", "dbt", "duckdb"],
) as dag:

    extract_ryanb = BashOperator(
        task_id="extract_ryanb",
        bash_command=(
            f"cd {EXTRACT_DIR} && python extract_mssql_to_parquet.py "
            f"--config config.yml --only "
            f"pol_vehicle pol_cvg pol_vehicleraw "
            f"premium_bi premium_pip premium_pd premium_coll premium_comp "
            f"premium_umbi premium_umpd premium_total_veh"
        ),
    )

    extract_claims = BashOperator(
        task_id="extract_claims",
        bash_command=(
            f"cd {EXTRACT_DIR} && python extract_mssql_to_parquet.py "
            f"--config config.yml --only t_loss_reserve"
        ),
    )

    dbt_deps = BashOperator(
        task_id="dbt_deps",
        bash_command=f"cd {DBT_DIR} && dbt deps",
    )

    dbt_build = BashOperator(
        task_id="dbt_build",
        bash_command=f"cd {DBT_DIR} && dbt build --target dev",
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=f"cd {DBT_DIR} && dbt test --target dev",
    )

    [extract_ryanb, extract_claims] >> dbt_deps >> dbt_build >> dbt_test

    # --- Alternative: per-model tasks via astronomer-cosmos ------------------
    # from cosmos import DbtTaskGroup, ProjectConfig, ProfileConfig
    # transform = DbtTaskGroup(
    #     project_config=ProjectConfig(DBT_DIR),
    #     profile_config=ProfileConfig(profile_name="nj_lr", target_name="dev",
    #                                  profiles_yml_filepath=DBT_DIR / "profiles.yml"),
    # )
    # [extract_ryanb, extract_claims] >> transform
