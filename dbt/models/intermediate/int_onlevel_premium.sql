{{ config(materialized='table') }}

-- Legacy: File2 L259-294.
--   1. Collapse UMBI + UMPD -> UM and TOTAL_VEH -> TOTAL (L259-264).
--   2. Re-aggregate per vehicle x collapsed-coverage (L266-270).
--   3. Pivot to the wide OLEP_<cov> columns on the vehicle grain (L274-291).
--   4. OLEP_OTHER = OLEP_TOTAL - (BI + PD + PIP + COMP + COLL + UM)  (L293-294).
--
-- Input stg_pol_premium is already long & pre-summed per (veh_unit_pk, cvg).

with collapsed as (
    select
        veh_unit_pk,
        case
            when cvg in ('UMBI', 'UMPD') then 'UM'
            when cvg = 'TOTAL_VEH'       then 'TOTAL'
            else cvg
        end as cvg,
        ol_prmm
    from {{ ref('stg_pol_premium') }}
),

regrouped as (
    select
        veh_unit_pk,
        cvg,
        sum(ol_prmm) as ol_prmm
    from collapsed
    group by veh_unit_pk, cvg
),

wide as (
    select
        veh_unit_pk,
        coalesce(max(case when cvg = 'BI'    then ol_prmm end), 0) as olep_bi,
        coalesce(max(case when cvg = 'PIP'   then ol_prmm end), 0) as olep_pip,
        coalesce(max(case when cvg = 'PD'    then ol_prmm end), 0) as olep_pd,
        coalesce(max(case when cvg = 'COLL'  then ol_prmm end), 0) as olep_coll,
        coalesce(max(case when cvg = 'COMP'  then ol_prmm end), 0) as olep_comp,
        coalesce(max(case when cvg = 'UM'    then ol_prmm end), 0) as olep_um,
        coalesce(max(case when cvg = 'TOTAL' then ol_prmm end), 0) as olep_total
    from regrouped
    group by veh_unit_pk
)

select
    *,
    olep_total - olep_bi - olep_pd - olep_pip - olep_comp - olep_coll - olep_um as olep_other
from wide
