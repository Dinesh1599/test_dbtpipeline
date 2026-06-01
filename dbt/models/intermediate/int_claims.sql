{{ config(materialized='table') }}

-- Legacy: File2 L445-460. Aggregate the scoped, coverage-mapped reserve records
-- to the claim-feature grain, then add report/closed-without-payment flags.
-- = tmp_NJfreq_clm.

with c as (
    select
        pol_num,
        clm_num,
        acc_mo,
        loss_dt,
        cvg,
        count(*) as feature_cnt,

        -- !!! FAITHFUL LEGACY QUIRK (File2 L449) !!!
        -- The legacy is COUNT(CASE WHEN RSV_STAT='CLOSE' THEN 1 ELSE 0 END).
        -- COUNT() ignores only NULLs, and the ELSE 0 is non-null, so this counts
        -- EVERY row — i.e. CLOSE_CNT always equals FEATURE_CNT. Reproduced
        -- exactly so CWOP_CNT below behaves identically to the source system.
        -- If you ever want the *intended* closed-feature count, switch to:
        --     sum(case when rsv_stat = 'CLOSE' then 1 else 0 end)
        count(case when rsv_stat = 'CLOSE' then 1 else 0 end) as close_cnt,

        sum(coalesce(loss_paid, 0) + coalesce(reserve_change, 0) - coalesce(recovery, 0)) as inc_loss,
        sum(coalesce(loss_paid, 0) - coalesce(recovery, 0))                                as paid_loss

    from {{ ref('stg_claims_loss_reserve') }}
    where cvg in ('BI', 'PD', 'PIP', 'COMP', 'COLL', 'OTHER', 'UM')
    group by pol_num, clm_num, acc_mo, loss_dt, cvg
)

select
    *,
    1 as rpt_cnt,                                                       -- File2 L457
    case when feature_cnt = close_cnt and paid_loss <= 0 then 1 else 0 end as cwop_cnt  -- File2 L458
from c
