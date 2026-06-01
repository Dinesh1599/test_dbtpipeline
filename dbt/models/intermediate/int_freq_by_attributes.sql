{{ config(materialized='table') }}

-- Exhibit 1 — NJauto_freq_by_attributes. ONE ROW PER POLICY TERM (POL_PK).
-- Legacy: File2 L464-609.
--
-- >>> VERIFY (grain — this is THE key reconstruction decision):
--     The claims attach (int_claims_polpk, legacy L615-626) joins this table on
--     POL_NUM + loss-date-in-window. That join is only 1:1 if this table has one
--     row per policy term. Two facts point that way: (a) Exhibit 1 already
--     reduces descriptive attributes with MAX(BI)/MAX(UIM_STACK)/MAX(TERR), and
--     (b) running with multi-row-per-POL_PK double-counted claim losses. So this
--     groups ONLY by the policy-term keys and MAX-reduces every descriptive
--     attribute. The vehicle-level measures are still SUMmed across the term.
--     If your file's Exhibit 1 truly splits rows by a per-vehicle attribute,
--     add that attribute to BOTH the group-by here and the accqtr pivot key.
--
-- Per-coverage claim columns (RPT_CNT_*, LOSS_*, RPTxCWOP_*) are typed NULL
-- placeholders at this stage in the legacy (claims attach is for Exhibit 2).

{% set wide = ['bi', 'pip', 'pd', 'coll', 'comp', 'um', 'total', 'other'] %}

with pol as (
    select * from {{ ref('int_policy_attributes') }}
)

select
    -- policy-term keys = the grain
    pol_num,
    pol_pk,
    orgl_pol_eff_dt,
    cur_term_eff_dt,
    pol_state_eff_dt,
    row_xptn_dt,
    end_dt,

    -- descriptive attributes, reduced to the term via MAX (>>> see VERIFY)
    max(agency)            as agency,
    max(ho_companion)      as ho_companion,
    max(homeowner)         as homeowner,
    max(bi_lmt)            as bi_lmt,
    max(singlemulticar)    as singlemulticar,
    max(pri_tenure)        as pri_tenure,
    max(pri_bi)            as pri_bi,
    max(max_exp)           as max_exp,
    max(fincl_resp_grp)    as fincl_resp_grp,
    max(undwrtg_tier)      as undwrtg_tier,
    max(comp_dscnt_typ)    as comp_dscnt_typ,
    max(full_cvg_flg)      as full_cvg_flg,
    max(mrrd_flg)          as mrrd_flg,
    max(paid_in_full_dscnt_flg) as paid_in_full_dscnt_flg,
    max(advd_qte_dscnt_flg)     as advd_qte_dscnt_flg,
    max(edoc_dscnt_apld_flg)    as edoc_dscnt_apld_flg,
    max(afnty_rt_grp)      as afnty_rt_grp,
    max(contns_ins_stat)   as contns_ins_stat,
    max(pay_pln)           as pay_pln,
    max(ppa_cnt)           as ppa_cnt,
    max(expcat)            as expcat,
    max(bi)                as bi,
    max(uim_stack)         as uim_stack,
    max(terr)              as terr,
    max(grgng_zip_cd)      as grgng_zip_cd,

    -- exposures (File2: EE_TOTAL plus the COLL/PD frequency variants)
    sum(ee)                                          as ee_total,
    sum(case when anul_prmm_coll > 0 then ee end)    as ee_coll,
    sum(case when anul_prmm_pd   > 0 then ee end)    as ee_pd,

    -- earned premium and on-level earned premium per coverage
    {%- for c in wide %}
    sum(anul_prmm_{{ c }} * ee) as ep_{{ c }},
    {%- endfor %}
    {%- for c in wide %}
    sum(olep_{{ c }} * ee) as olep_{{ c }},
    {%- endfor %}

    -- claim columns attached in Exhibit 2; NULL here (faithful to L470-534)
    cast(null as integer) as rpt_cnt_pd,
    cast(null as integer) as rpt_cnt_coll,
    cast(null as integer) as rpt_cnt_pol,
    cast(null as integer) as rptxcwop_pd,
    cast(null as integer) as rptxcwop_coll,
    cast(null as integer) as rptxcwop_pol,
    cast(null as double)  as loss_pd,
    cast(null as double)  as loss_coll,
    cast(null as double)  as loss_pol

from pol
group by pol_num, pol_pk, orgl_pol_eff_dt, cur_term_eff_dt,
         pol_state_eff_dt, row_xptn_dt, end_dt
