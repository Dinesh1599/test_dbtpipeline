{{ config(materialized='table') }}

-- Builds the attribute half of tmp_NJfreq_pol and is the canonical vehicle-grain
-- policy table the rest of the pipeline joins to.
-- Legacy: File2 L313-508 (recodes + backfills) over int_policy_premium.
--
-- CONFIDENCE
--   Confident (CASE inputs are real source columns): PRI_TENURE, PRI_BI,
--     MAX_EXP, AGENCY, HO_COMPANION, HOMEOWNER, BI_LMT, SINGLEMULTICAR.
--   >>> VERIFY: UIM_STACK reads the UIM_stack column, which is a CONVERT(NULL)
--     placeholder in the SELECT whose population step is NOT in either file. If
--     it truly stays NULL, the recode below yields 'No Coverage' for everyone —
--     faithful to the code as written, but likely not the intent. Wire the real
--     source in if there is one.
--   External-source columns (MIN_EXP, MARKET, ISI, IA_AGENT_APPT_YR, GEOregion,
--     PAY_Mapping, CLEAN_LVL, EXPCAT) are populated in the legacy from tables
--     that are NOT in these two files. They are emitted as typed NULLs so the
--     downstream group-bys compile; point them at their real sources to finish.

with p as (
    select * from {{ ref('int_policy_premium') }}
),

raw as (
    select * from {{ ref('stg_pol_vehicleraw') }}
),

with_src as (
    select
        p.*,
        raw.final_bus_src,
        -- UIM_stack placeholder input (see VERIFY above). NULL unless sourced.
        cast(null as varchar) as uim_stack_src
    from p
    left join raw on p.veh_unit_pk = raw.veh_unit_pk
),

recoded as (
    select
        *,

        -- File2 L313-316
        case when uim_stack_src is null or uim_stack_src = '' then 'No Coverage'
             else uim_stack_src end as uim_stack,

        -- File2 L317-332  (input: LPS_DAY_CT — note the legacy reuses this column
        -- as a BI-limit string, not a day count; preserved as written)
        -- >>> VERIFY(img6): the '10000' literal on the first WHEN had no commas in
        --     the photo; confirm whether it is '10000' or '10,000'.
        case lps_day_ct
            when '10000'           then 'Low'
            when '15,000/30,000'   then 'Low'
            when '20,000/40,000'   then 'Low'
            when '25,000/50,000'   then 'Low'
            when '35,000/70,000'   then 'Low'
            when 'No limit'        then 'Low'
            when '100,000 CSL'     then 'Medium'
            when '35,000/80,000'   then 'Medium'
            when '50,000/100,000'  then 'Medium'
            when '100,000/300,000' then 'High'
            when '300,000 CSL'     then 'High'
            when '250,000/500,000' then 'Very High'
            when '500,000/500,000' then 'Very High'
            when '500,000 CSL'     then 'Very High'
        end as pri_tenure,

        -- File2 L333-339
        case pri_bi_lmt_cat
            when 'High'     then 'B High'
            when 'Low'      then 'D Low'
            when 'MED'      then 'C Medium'
            when 'VeryHigh' then 'A Very High'
            else pri_bi_lmt_cat
        end as pri_bi,

        -- File2 L340-346
        case max_drv_exp_grp
            when 'H'  then 'B High'
            when 'L'  then 'D Low'
            when 'M'  then 'C Medium'
            when 'VH' then 'A Very High'
            else max_drv_exp_grp
        end as max_exp,

        -- File2 L347-361
        case when final_bus_src = 'eSales' then 'eSales' else agcy_name end as agency,

        -- File2 L491-500
        case
            when ho_lvl_typ in ('HO_1', 'CONDO_1')    then 'A Companion Home'
            when ho_lvl_typ in ('HO_2', 'CONDO_2')    then 'B Superpreferred Home'
            when ho_lvl_typ in ('HO_3', 'CONDO_3')    then 'C Preferred Home'
            when ho_lvl_typ in ('HO_4', 'CONDO_4')    then 'D Home'
            when ho_lvl_typ = 'RNTL_1'                then 'E Companion Renter'
            when ho_lvl_typ in ('RNTL_2', 'RNTL_3')   then 'G Other Renter'
            when ho_lvl_typ = 'RNTL_5'                then 'F Renter Endorsement'
            else 'H NO discount'
        end as ho_companion,

        -- File2 L501
        case when ho_lvl_typ like 'HO%' or ho_lvl_typ like 'CONDO%' then 'Y' else 'N' end as homeowner,

        -- File2 L503-508  (input: BI limit text from int_bi_desc)
        case
            when bi in ('250,000/500,000', '500,000/500,000', '500,000 CSL')  then 'A Very High'
            when bi in ('100,000/300,000', '300,000 CSL')                     then 'B High'
            when bi in ('100,000 CSL', '35,000/80,000', '50,000/100,000')     then 'C Medium'
            else 'D Low'
        end as bi_lmt,

        -- File2 L477
        case when drv_veh_combo like 'DV1%' then 'SINGLE' else 'MULTI' end as singlemulticar,

        -- File2 L364-372: vehicles on the policy.
        -- >>> VERIFY: confirm count(*) vs count(distinct veh_unit_pk).
        count(*) over (partition by pol_pk) as ppa_cnt,

        -- File2 L375-391: territory backfilled from the lowest-VEH_UNIT_PK row.
        first_value(terrty_cd) over (
            partition by pol_pk order by veh_unit_pk
            rows between unbounded preceding and unbounded following
        ) as terr,

        -- File2 L394-408: EXPCAT keys off the lowest POL_PK per POL_NUM, but its
        -- value comes from a table NOT in these files. Flag the anchor row; the
        -- value itself is left NULL for you to source.
        case when pol_pk = min(pol_pk) over (partition by pol_num) then 1 else 0 end as is_expcat_anchor,

        -- External-source placeholders (typed NULLs; wire to real sources).
        cast(null as varchar) as expcat,
        cast(null as varchar) as min_exp,
        cast(null as varchar) as market,
        cast(null as varchar) as isi,
        cast(null as varchar) as ia_agent_appt_yr,
        cast(null as varchar) as georegion,
        cast(null as varchar) as pay_mapping,
        cast(null as varchar) as clean_lvl

    from with_src
)

select * from recoded
