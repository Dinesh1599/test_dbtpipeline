{#
  unpivot_accqtr_premium
  ----------------------
  Replaces the legacy Exhibit-2 premium loop (File2 ~L709-731). For each
  coverage the procedure ran:

      SELECT POL_NUM, POL_PK, YYYY, YYYYQT, CVG='<cov>',
             EE   = SUM(CASE WHEN ANUL_PRMM_<cov> > 0 THEN EE ELSE 0 END),
             EP   = SUM(ANUL_PRMM_<cov> * EE),
             OLEP = SUM(OLEP_<cov> * EE)
      ... GROUP BY POL_NUM, POL_PK, YYYY, YYYYQT
      UNION ALL (next coverage)

  Turning the wide ANUL_PRMM_<cov> / OLEP_<cov> columns on the exploded
  policy-month table back into a long (… , cvg, ee, ep, olep) shape. Claim
  measures are NULL here; they get joined in downstream.

  Args
    relation  : {{ ref('int_policy_month') }} (wide, one row per veh x quarter)
    coverages : list of coverage codes (var: accqtr_coverages)
#}
{% macro unpivot_accqtr_premium(relation, coverages) %}
{%- for cov in coverages %}
select
    pol_num,
    pol_pk,
    yyyy,
    yyyyqt,
    '{{ cov }}' as cvg,
    sum(case when anul_prmm_{{ cov | lower }} > 0 then ee else 0 end) as ee,
    sum(anul_prmm_{{ cov | lower }} * ee)                              as ep,
    sum(olep_{{ cov | lower }} * ee)                                   as olep
from {{ relation }}
group by pol_num, pol_pk, yyyy, yyyyqt
{%- if not loop.last %}
union all
{%- endif %}
{%- endfor %}
{% endmacro %}
