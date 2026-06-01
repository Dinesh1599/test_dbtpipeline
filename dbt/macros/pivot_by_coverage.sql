{#
  pivot_by_coverage
  -----------------
  Replaces the legacy Exhibit-2 dynamic pivot (File2 ~L832-896), where the
  procedure looped over coverages and, per coverage, ran ALTER TABLE ADD +
  UPDATE ... WHERE CVG='<cov>' to splay a long (key, cvg, measures) table into
  wide per-coverage columns.

  Here that becomes a single conditional-aggregation pass:
      max(case when cvg = '<cov>' then <measure> end) as <measure>_<cov>

  Args
    relation   : a {{ ref(...) }} or {{ source(...) }} to the LONG table
    key_cols   : list of grouping columns (the row grain of the wide output)
    measures   : list of measure columns to splay
    coverages  : list of coverage codes to make columns for
    cvg_col    : name of the coverage column in `relation` (default 'cvg')
#}
{% macro pivot_by_coverage(relation, key_cols, measures, coverages, cvg_col='cvg') %}
{%- set key_csv = key_cols | join(',\n    ') -%}
select
    {{ key_csv }}
    {%- for cov in coverages %}
    {%- for m in measures %}
    , max(case when {{ cvg_col }} = '{{ cov }}' then {{ m }} end) as {{ m }}_{{ cov }}
    {%- endfor %}
    {%- endfor %}
from {{ relation }}
group by
    {{ key_csv }}
{% endmacro %}
