{{ config(materialized='table') }}

-- Builds the numeric half of tmp_NJfreq_pol (vehicle grain).
-- Legacy: File2 L121-132 (END_DT cap), L149-197 (premium + annualization),
--         L299-308 (END_DT re-cap + earned exposure).
--
-- END_DT note (>>> VERIFY): the legacy first set END_DT from MAX(LSTDAY) of the
-- monthly calendar tmp_NJfreq_mon WHERE LSTDAY < GETDATE() (L121-132), then
-- capped END_DT = LEAST(END_DT, ROW_XPTN_DT) (L299-301). That monthly table was
-- never in the photos, so the as-of date is the var `valuation_date`. Confirm
-- it matches the run you are reproducing.

with base as (
    select * from {{ ref('stg_pol_vehicle') }}
),

ft as (
    select * from {{ ref('int_ft_premium') }}
),

ol as (
    select * from {{ ref('int_onlevel_premium') }}
),

bi as (
    select * from {{ ref('int_bi_desc') }}
),

joined as (
    select
        base.*,

        -- END_DT: as-of valuation date, never later than policy expiry.
        least(date '{{ var("valuation_date") }}', base.row_xptn_dt) as end_dt,

        bi.bi,

        coalesce(ft.ft_prmm_bi, 0)    as ft_prmm_bi,
        coalesce(ft.ft_prmm_pd, 0)    as ft_prmm_pd,
        coalesce(ft.ft_prmm_coll, 0)  as ft_prmm_coll,
        coalesce(ft.ft_prmm_comp, 0)  as ft_prmm_comp,
        coalesce(ft.ft_prmm_pip, 0)   as ft_prmm_pip,
        coalesce(ft.ft_prmm_um, 0)    as ft_prmm_um,
        coalesce(ft.ft_prmm_total, 0) as ft_prmm_total,

        ol.olep_bi,
        ol.olep_pip,
        ol.olep_pd,
        ol.olep_coll,
        ol.olep_comp,
        ol.olep_um,
        ol.olep_total,
        ol.olep_other

    from base
    left join ft  on base.veh_unit_pk = ft.veh_unit_pk
    left join ol  on base.veh_unit_pk = ol.veh_unit_pk
    left join bi  on base.veh_unit_pk = bi.veh_unit_pk
    -- File2 L132: drop rows whose state-effective date is on/after END_DT.
    where base.pol_state_eff_dt < least(date '{{ var("valuation_date") }}', base.row_xptn_dt)
),

annualized as (
    select
        *,
        -- File2 L187-193: annualize each coverage to a 12-month basis.
        case when pol_term > 0 then 12.0 / pol_term * ft_prmm_bi    else 0 end as anul_prmm_bi,
        case when pol_term > 0 then 12.0 / pol_term * ft_prmm_pd    else 0 end as anul_prmm_pd,
        case when pol_term > 0 then 12.0 / pol_term * ft_prmm_coll  else 0 end as anul_prmm_coll,
        case when pol_term > 0 then 12.0 / pol_term * ft_prmm_comp  else 0 end as anul_prmm_comp,
        case when pol_term > 0 then 12.0 / pol_term * ft_prmm_pip   else 0 end as anul_prmm_pip,
        case when pol_term > 0 then 12.0 / pol_term * ft_prmm_um    else 0 end as anul_prmm_um,
        case when pol_term > 0 then 12.0 / pol_term * ft_prmm_total else 0 end as anul_prmm_total
    from joined
)

select
    *,
    -- File2 L195-197: residual "other" annual premium, rounded to whole dollars.
    round(anul_prmm_total - anul_prmm_bi - anul_prmm_pd - anul_prmm_pip
          - anul_prmm_comp - anul_prmm_coll - anul_prmm_um, 0) as anul_prmm_other,

    -- File2 L303-308: earned exposure = earned days / full annual term.
    cast(
        cast(date_diff('day', pol_state_eff_dt, end_dt) as decimal(7,4))
        / nullif(cast(date_diff('day', cur_term_eff_dt,
                                cur_term_eff_dt + interval 1 year) as decimal(7,4)), 0)
        as decimal(7,5)
    ) as ee
from annualized
