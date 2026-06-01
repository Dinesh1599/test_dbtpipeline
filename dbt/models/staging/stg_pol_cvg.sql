{{ config(materialized='view') }}

-- Source: PRIME3_POL_ACTUARIAL_all_pk_thru_2025Q2_CVG_DW
-- Coverage grain. Feeds the full-term premium rollup (int_ft_premium) and the
-- BI limit description (int_policy_premium). Legacy reads it at File2 L150-166.

select
    veh_unit_pk,
    cvg_cd,
    full_term_prmm_total,
    cntrbt_to_prmm_flg,
    lmt_1_desc
from {{ source('ryanb', 'pol_cvg') }}
