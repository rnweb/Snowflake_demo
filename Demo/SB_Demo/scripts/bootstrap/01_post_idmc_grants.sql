-- ============================================================================
-- Post-IDMC grants — run AFTER the first IDMC CDI run of m_SB_Riesgo_por_Rubro
-- ============================================================================
-- RIESGO_POR_RUBRO is created by IDMC (not Terraform), so this grant cannot
-- live in Terraform: on a fresh trial the table does not exist at apply time.
--
-- Least privilege on purpose: FR_BI_ANALYST sees only the aggregated IDMC
-- output, never COMERCIOS_MAESTRO or anything else in the landing schema.
-- Validated 2026-10-20 in Power BI Desktop (Navigator shows
-- IDMC_LANDING_SCHEMA [1] and no STAGING_SCHEMA for DEMO_ANALYST).
-- ============================================================================

USE ROLE FR_DEMO_ADMIN;

GRANT USAGE  ON SCHEMA SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA
  TO ROLE FR_BI_ANALYST;

GRANT SELECT ON TABLE  SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA.RIESGO_POR_RUBRO
  TO ROLE FR_BI_ANALYST;

-- Same RLS as the source table: the aggregate is grouped by RUBRO +
-- UNIDAD_NEGOCIO, so a RETAIL analyst must not see PYME/CORPORATIVO totals.
-- (Requires APPLY ROW ACCESS POLICY — see 00_accountadmin_bootstrap.sql.)
ALTER TABLE SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA.RIESGO_POR_RUBRO
    ADD ROW ACCESS POLICY SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.RLS_BUSINESS_UNIT
    ON (UNIDAD_NEGOCIO);

-- Checks
-- As FR_DEMO_ADMIN : 33 rows (11 rubros x 3 units), SUM(QTD_TRANSACCIONES) = 18000
-- As FR_BI_ANALYST : 11 rows, only RETAIL,          SUM(QTD_TRANSACCIONES) = 5849
-- SELECT COUNT(*), SUM(QTD_TRANSACCIONES)
--   FROM SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA.RIESGO_POR_RUBRO;
