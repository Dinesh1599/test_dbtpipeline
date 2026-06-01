{{ config(materialized='table') }}

-- Legacy: File2 L691-731 (premium side of NJauto_freq_LR_AccQtr_attributes_raw).
-- The per-coverage INSERT loop becomes one UNION ALL via the unpivot macro.
-- Grain: (pol_num, pol_pk, yyyy, yyyyqt, cvg) with ee / ep / olep.

{{ unpivot_accqtr_premium(ref('int_policy_month'), var('accqtr_coverages')) }}
