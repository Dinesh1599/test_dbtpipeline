{{ config(materialized='table') }}

-- Legacy: File2 L137-140. The BI limit text, taken from the coverage grain:
--   BI = CASE WHEN CVG_CD = 'BI' AND LMT_1_DESC IS NOT NULL THEN LMT_1_DESC END
-- Reduced to the vehicle grain via MAX (a vehicle has at most one BI coverage).

select
    veh_unit_pk,
    max(case when cvg_cd = 'BI' and lmt_1_desc is not null then lmt_1_desc end) as bi
from {{ ref('stg_pol_cvg') }}
group by veh_unit_pk
