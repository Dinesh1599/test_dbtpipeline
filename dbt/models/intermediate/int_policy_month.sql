{{ config(materialized='table') }}

-- Legacy: File2 L634-688 (= tmp_NJfreq_POL_mon).
-- Explode each vehicle/policy across every quarter its earned period overlaps,
-- clamp the start/end to the quarter window, and recompute earned exposure for
-- the slice.
--
--   STT_DT = greatest(pol_state_eff_dt, quarter first day)      (L681)
--   slice end = least(end_dt, quarter lstday)                   (L677-678)
--   EE_qtr = earned days in slice / full annual term            (L683-687)
--
-- Overlap test (L662-664): policy active period [pol_state_eff_dt, end_dt)
-- intersects quarter [fstday, lstday). Only quarters from start_yyyyqt forward.

with pol as (
    select * from {{ ref('int_policy_attributes') }}
),

q as (
    select * from {{ ref('int_quarters') }}
    where yyyyqt >= {{ var('start_yyyyqt') }}
),

exploded as (
    select
        pol.*,
        q.yyyy,
        q.yyyyqt,
        q.fstday,
        q.lstday,
        greatest(pol.pol_state_eff_dt, q.fstday) as stt_dt,
        least(pol.end_dt, q.lstday)              as slice_end_dt
    from pol
    join q
      -- 3-way overlap: policy starts before quarter ends AND ends after it starts
      on pol.pol_state_eff_dt <  q.lstday
     and pol.end_dt           >  q.fstday
)

select
    * exclude (ee),   -- drop the policy-level EE; replace with the quarter slice EE
    cast(
        cast(date_diff('day', stt_dt, slice_end_dt) as decimal(7,4))
        / nullif(cast(date_diff('day', cur_term_eff_dt,
                                cur_term_eff_dt + interval 1 year) as decimal(7,4)), 0)
        as decimal(7,4)
    ) as ee
from exploded
