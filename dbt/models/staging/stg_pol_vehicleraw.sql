{{ config(materialized='view') }}

-- Source: PRIME3_POL_ACTUARIAL_all_pk_thru_2025Q2_VEHICLERAW
-- Used only to bring in Final_BUS_SRC, which drives the eSales AGENCY recode.
-- Legacy: File2 L356-361.

select
    veh_unit_pk,
    final_bus_src
from {{ source('ryanb', 'pol_vehicleraw') }}
