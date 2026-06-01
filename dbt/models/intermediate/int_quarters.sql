{{ config(materialized='table') }}

-- Legacy: File2 L1-23. Quarter calendar 2017-2025.
--   YYYYQT  = year * 100 + quarter   (e.g. 201901..201904)
--   FSTDAY  = first day of the quarter (months 1,4,7,10)
--   LSTDAY  = first day of the NEXT quarter  (exclusive upper bound; the legacy
--             name "last day" is a misnomer — it is FSTDAY + 3 months)

with years as (
    select * from range(2017, 2026) as t(yyyy)    -- 2017..2025 inclusive
),

q as (
    select * from (values (1, 1), (2, 4), (3, 7), (4, 10)) as v(qtr, start_month)
)

select
    years.yyyy,
    years.yyyy * 100 + q.qtr                          as yyyyqt,
    make_date(years.yyyy, q.start_month, 1)           as fstday,
    make_date(years.yyyy, q.start_month, 1) + interval 3 month as lstday
from years
cross join q
