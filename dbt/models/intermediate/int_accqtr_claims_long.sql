{{ config(materialized='table') }}

-- Legacy: File2 L737-756 (claims side of the accident-quarter raw table; the
-- UPDATE that matched claims onto premium rows by POL_PK + CVG + YYYYQT).
-- Grain: (pol_pk, cvg, yyyyqt).
--
--   RPT_CNT   = SUM(rpt_cnt)            (report count)
--   RPTxCWOP  = SUM(rpt_cnt - cwop_cnt) (reports excluding closed-without-pay)
--   INCURRED  = SUM(inc_loss)
--   PAID      = SUM(paid_loss)

select
    pol_pk,
    cvg,
    yyyyqt,
    sum(rpt_cnt)                as rpt_cnt,
    sum(rpt_cnt - cwop_cnt)     as rptxcwop,
    sum(inc_loss)               as incurred,
    sum(paid_loss)              as paid
from {{ ref('int_claims_polpk') }}
group by pol_pk, cvg, yyyyqt
