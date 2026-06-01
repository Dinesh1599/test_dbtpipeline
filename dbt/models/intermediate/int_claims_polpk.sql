{{ config(materialized='table') }}

-- Legacy: File2 L615-626 (= tmp_NJfreq_clm_POLPK).
-- Attach POL_PK to each claim feature by matching the policy that was in force
-- at the loss date, and derive the accident quarter from ACC_MO.
--
-- Join target (>>> VERIFY L622-623): the live legacy join is to
-- NJauto_freq_by_attributes (here int_freq_by_attributes) — the policy-TERM
-- grain — with "JOIN tmp_NJfreq_pol" commented out on L622. Using the term-grain
-- table avoids fanning each claim across every vehicle on the policy. If your
-- file actually has L622 live instead, swap the ref to int_policy_attributes.
--
-- This is the ~39.7M-row, 26-minute join (legacy comment L759). DuckDB handles
-- the range join far better, but it is still the heaviest step — keep an eye on
-- memory_limit / temp_directory in profiles.

with clm as (
    select * from {{ ref('int_claims') }}
),

pol as (
    select
        pol_num,
        pol_pk,
        pol_state_eff_dt,
        row_xptn_dt
    from {{ ref('int_freq_by_attributes') }}
)

select
    clm.*,
    pol.pol_pk,

    -- File2 L619: YYYYQT from ACC_MO (an integer like 201903).
    --   year*100 + quarter, quarter = floor((month-1)/3)+1
    (cast(left(cast(clm.acc_mo as varchar), 4) as integer) * 100)
      + (((cast(right(cast(clm.acc_mo as varchar), 2) as integer) - 1) // 3) + 1) as yyyyqt

from clm
join pol
  on clm.pol_num = pol.pol_num
 and clm.loss_dt >= pol.pol_state_eff_dt
 and clm.loss_dt <  pol.row_xptn_dt
