{{ config(
    materialized='external',
    location=env_var('NJ_LR_OUTPUT_DIR', 'output') ~ '/' ~ this.identifier ~ '.parquet'
) }}

-- Exhibit 1 final output (parquet). Legacy: NJauto_freq_by_attributes.
-- Adds the GEOregion column the legacy LEFT JOINed on at L604-609; its source
-- table is external to these two files, so it carries through as NULL until you
-- wire it in int_policy_attributes.

select
    *,
    cast(null as varchar) as georegion
from {{ ref('int_freq_by_attributes') }}
