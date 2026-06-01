{{ config(materialized='view') }}

-- Source: PRIME3_POL_ACTUARIAL_all_pk_thru_2025Q2_Vehicle_DW
-- Legacy: File2 L31-109 (SELECT list) + L107-109 (WHERE).
--
-- Only GENUINELY-SOURCED columns are selected here. The legacy SELECT also
-- created ~30 CONVERT(<type>, NULL) placeholder columns (BI, UIM_stack, END_DT,
-- EE, FT_PRMM_*, ANUL_PRMM_*, OLEP_*, TERR, EXPCAT, PPA_CNT, etc.). Those are
-- not data — they are empty slots the procedure filled with later UPDATE
-- statements. In dbt they become derived columns in the intermediate layer, so
-- they do NOT belong in staging.

with src as (

    select * from {{ source('ryanb', 'pol_vehicle') }}

)

select
    -- keys
    veh_unit_pk,
    pol_pk,
    pol_num,
    co_cd,
    veh_seq_num,

    -- dates
    orgl_pol_eff_dt,
    cur_term_eff_dt,
    pol_state_eff_dt,
    row_xptn_dt,
    src_updt_dt,

    -- agency / distribution
    agcy_name,
    agcy_cd,
    prdcr_cd,

    -- policy attributes used by the recodes / group-bys downstream
    pol_stat,
    pol_term,
    drv_veh_combo,
    paid_in_full_dscnt_flg,
    fincl_resp_grp,
    undwrtg_tier,
    comp_dscnt_typ,
    ho_lvl_typ,
    full_cvg_flg,
    mrrd_flg,
    advd_qte_dscnt_flg,
    edoc_dscnt_apld_flg,
    afnty_rt_grp,
    lps_day_ct,
    contns_ins_stat,
    most_rcnt_carr_tenure_len,
    pri_bi_lmt_cat,
    pri_carr_cat,
    max_drv_exp_grp,
    pay_pln,
    mnths_with_prac,
    terrty_cd,
    grgng_zip_cd,
    rcf_rnwl_cap_fctr

from src
-- File2 L107-109
where row_xptn_dt >= date '2019-01-01'
  and pol_stat in ('ACTIVE', 'EXPIRED')
  and pol_state_eff_dt < row_xptn_dt
