{{ config(materialized='view') }}

-- Source: CO1DAGWPV02.CLAIMS_NJ.DBO.T_LOSS_RESERVE  (WITH (NOLOCK) in legacy)
-- Legacy: File2 L414-433 (filters) + L418-426 (CVG mapping).
--
-- The WHERE clause is pushed down to staging so every downstream claims model
-- works off the already-scoped set. The CVG derivation maps PERIL_DESC / CVG_CD
-- onto the seven analysis coverages plus an 'OPTIONFRILLS' catch-all; the
-- claims aggregate later keeps only the seven.

with src as (

    select * from {{ source('claims', 't_loss_reserve') }}

)

select
    pol_num,
    clm_num,
    acc_mo,
    loss_dt,
    rsv_stat,
    loss_paid,
    reserve_change,
    recovery,

    -- File2 L418-426: coverage normalization
    case
        when peril_desc in ('BI', 'PD', 'PIP') then peril_desc
        when cvg_cd     in ('COLL', 'COMP')    then cvg_cd
        when peril_desc in ('UMBI', 'UMPD')    then 'UM'
        when cvg_cd     in ('RENTAL', 'TOWING') then 'OTHER'
        else 'OPTIONFRILLS'
    end as cvg

from src
-- File2 L428-433
where prod_cd = 'PA'
  and acc_mo >= {{ var('start_yyyyqt') // 100 * 100 + 1 }}   -- 201901
  and co_cd in ('ALN_HPCIC', 'ALN_PIC', 'ALN_PSIA', 'PSIA', 'ALN_TEACH')
  and policy_state = 'NJ'
  and prmy_acc_cause <> 'rent'
  and (void_flg is null or void_flg = 'N')
