{{ config(materialized='view') }}

-- Sources: PRIME3_..._Premium_<cov>  (eight tables)
-- Legacy: File2 L200-256 — the first WHILE loop built tmp_OL_PRMM_<cov> for each
-- coverage (summing 'TotPrem', or 'Total' for TOTAL_VEH) then UNIONed them into
-- OL_PRMM_all_cov. That whole loop collapses to this one UNION ALL, driven by
-- the var `premium_sources` (coverage -> premium column name).
--
-- Output is LONG: (veh_unit_pk, cvg, ol_prmm), pre-aggregated per vehicle.
-- The UMBI/UMPD -> UM and TOTAL_VEH -> TOTAL collapse happens next, in
-- int_onlevel_premium.

{% set premium_sources = var('premium_sources') %}

{% for cov, prem_col in premium_sources.items() %}
select
    veh_unit_pk,
    '{{ cov }}' as cvg,
    sum(coalesce({{ prem_col | lower }}, 0)) as ol_prmm
from {{ source('ryanb', 'premium_' ~ cov | lower) }}
group by veh_unit_pk
{% if not loop.last %}union all{% endif %}
{% endfor %}
