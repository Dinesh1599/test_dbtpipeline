{{ config(materialized='table') }}

-- Legacy: File2 L804-822 (= AccQtr_attributes). Collapse the premium raw table
-- to POL_PK x YYYYQT x CVG, attach the claim rollup on the same key, and carry
-- the six measures that get pivoted wide in the mart.
-- LOSS uses incurred (inc_loss); switch to `paid` if your exhibit reports paid.

with prem as (
    select
        pol_pk,
        yyyyqt,
        cvg,
        sum(ee)   as ee,
        sum(ep)   as ep,
        sum(olep) as olep
    from {{ ref('int_accqtr_premium_long') }}
    group by pol_pk, yyyyqt, cvg
),

clm as (
    select * from {{ ref('int_accqtr_claims_long') }}
)

select
    prem.pol_pk,
    prem.yyyyqt,
    prem.cvg,
    prem.ee,
    prem.ep,
    prem.olep,
    coalesce(clm.rpt_cnt, 0)  as rpt_cnt,
    coalesce(clm.rptxcwop, 0) as rptxcwop,
    coalesce(clm.incurred, 0) as loss
from prem
left join clm
  on prem.pol_pk = clm.pol_pk
 and prem.cvg    = clm.cvg
 and prem.yyyyqt = clm.yyyyqt
