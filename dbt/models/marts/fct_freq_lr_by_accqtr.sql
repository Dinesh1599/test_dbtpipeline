{{ config(
    materialized='external',
    location=env_var('NJ_LR_OUTPUT_DIR', 'output') ~ '/' ~ this.identifier ~ '.parquet'
) }}

-- Exhibit 2 final output (parquet) — Frequency & Loss Ratio by Accident Quarter.
-- Legacy: NJauto_freq_LR_AccQtr_attributes (File2 L765-896).
--
-- The legacy's two transactioned DROP/ADD/UPDATE loops that splayed the six
-- measures into per-coverage columns collapse to one pivot_by_coverage() pass.
-- Then the policy dimensions are joined on (one row per POL_PK from Exhibit 1).
--
-- Resulting per-coverage columns, for cov in {{ var('accqtr_coverages') }}:
--   ee_<cov>, ep_<cov>, olep_<cov>, loss_<cov>, rpt_cnt_<cov>, rptxcwop_<cov>

with pivoted as (

    {{ pivot_by_coverage(
        relation = ref('int_accqtr_combined'),
        key_cols = ['pol_pk', 'yyyyqt'],
        measures = ['ee', 'ep', 'olep', 'loss', 'rpt_cnt', 'rptxcwop'],
        coverages = var('accqtr_coverages')
    ) }}

),

-- Dimensions reduced to ONE row per POL_PK.
-- >>> VERIFY (grain — surfaced by a uniqueness test on synthetic data): Exhibit
--     1 (int_freq_by_attributes) can hold MORE THAN ONE row per POL_PK when a
--     multi-vehicle policy has vehicles with differing per-vehicle attributes
--     (e.g. single/multi car, BI limit). Joining that straight onto the
--     accident-quarter table fans out the POL_PK x YYYYQT grain. The legacy
--     final table is described as keyed by POL_PK x YYYYQT, and Exhibit 1 itself
--     reduces descriptive attributes with MAX(), so we reduce to POL_PK here the
--     same way. If your file's final exhibit instead SPLITS by per-vehicle
--     attribute (i.e. its true grain is POL_PK x YYYYQT x attribute-combo), drop
--     this rollup and add the splitting attributes to the pivot key + this join.
dims as (
    select
        pol_pk,
        max(pol_num)          as pol_num,
        max(orgl_pol_eff_dt)  as orgl_pol_eff_dt,
        max(cur_term_eff_dt)  as cur_term_eff_dt,
        max(pol_state_eff_dt) as pol_state_eff_dt,
        max(row_xptn_dt)      as row_xptn_dt,
        max(end_dt)           as end_dt,
        max(agency)           as agency,
        max(ho_companion)     as ho_companion,
        max(homeowner)        as homeowner,
        max(bi_lmt)           as bi_lmt,
        max(singlemulticar)   as singlemulticar,
        max(pri_tenure)       as pri_tenure,
        max(pri_bi)           as pri_bi,
        max(max_exp)          as max_exp,
        max(fincl_resp_grp)   as fincl_resp_grp,
        max(undwrtg_tier)     as undwrtg_tier,
        max(comp_dscnt_typ)   as comp_dscnt_typ,
        max(full_cvg_flg)     as full_cvg_flg,
        max(mrrd_flg)         as mrrd_flg,
        max(paid_in_full_dscnt_flg) as paid_in_full_dscnt_flg,
        max(advd_qte_dscnt_flg)     as advd_qte_dscnt_flg,
        max(edoc_dscnt_apld_flg)    as edoc_dscnt_apld_flg,
        max(afnty_rt_grp)     as afnty_rt_grp,
        max(contns_ins_stat)  as contns_ins_stat,
        max(pay_pln)          as pay_pln,
        max(ppa_cnt)          as ppa_cnt,
        max(expcat)           as expcat,
        max(bi)               as bi,
        max(uim_stack)        as uim_stack,
        max(terr)             as terr,
        max(grgng_zip_cd)     as grgng_zip_cd
    from {{ ref('int_freq_by_attributes') }}
    group by pol_pk
)

select
    pivoted.*,
    dims.* exclude (pol_pk)
from pivoted
left join dims
  on pivoted.pol_pk = dims.pol_pk
