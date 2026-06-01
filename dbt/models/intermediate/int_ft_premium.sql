{{ config(materialized='table') }}

-- Legacy: File2 L150-166. Roll the coverage grain (stg_pol_cvg) up to the
-- vehicle grain, splitting FULL_TERM_PRMM_TOTAL into the coverage buckets by
-- CVG_CD. Only premium-bearing coverages count (CNTRBT_TO_PRMM_FLG = 'Y').
--
-- >>> VERIFY(img20): the IN(...) lists below were read from a clear frame, but
--     confirm the PIP and UM member lists and the TOTAL exclusion list against
--     the file — they are long and easy to mis-transcribe.

with cvg as (
    select * from {{ ref('stg_pol_cvg') }}
    where cntrbt_to_prmm_flg = 'Y'
)

select
    veh_unit_pk,

    sum(case when cvg_cd = 'BI'   then coalesce(full_term_prmm_total, 0) else 0 end) as ft_prmm_bi,
    sum(case when cvg_cd = 'PD'   then coalesce(full_term_prmm_total, 0) else 0 end) as ft_prmm_pd,
    sum(case when cvg_cd = 'COLL' then coalesce(full_term_prmm_total, 0) else 0 end) as ft_prmm_coll,
    sum(case when cvg_cd = 'COMP' then coalesce(full_term_prmm_total, 0) else 0 end) as ft_prmm_comp,

    sum(case when cvg_cd in ('MP','MB','ILB','ADB','FEB','CFPB','EMB','PIP','EXTRA_PIP','EMP','OBEL')
             then coalesce(full_term_prmm_total, 0) else 0 end) as ft_prmm_pip,

    sum(case when cvg_cd in ('UM','UIM','UMUIM','UMPD','SUMUIM','SUM_CSL')
             then coalesce(full_term_prmm_total, 0) else 0 end) as ft_prmm_um,

    sum(case when cvg_cd not in ('NCR_ALA','LOAN_ALA','YANKEE_FEE','PREM_PAK','ACC_FORG','PREF_PAK')
             then coalesce(full_term_prmm_total, 0) else 0 end) as ft_prmm_total

from cvg
group by veh_unit_pk
