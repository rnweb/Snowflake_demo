-- C05: deployment traceability. Called by the Azure DevOps CD stage:
--   dbt run-operation log_deployment --target ci_prod --args "{build_id: .., commit: .., author: .., source_ref: ..}"
-- Writes one row per deploy and stamps the deployed view with its version.
{% macro log_deployment(build_id, commit, author, source_ref) %}
    {% set sql %}
        insert into {{ target.database }}.GOVERNANCE_SCHEMA.DEPLOYMENT_LOG
            (BUILD_ID, GIT_COMMIT, AUTHOR, SOURCE_REF, TARGET_ENV, DEPLOYED_AT)
        values ('{{ build_id }}', '{{ commit }}', '{{ author | replace("'", "") }}',
                '{{ source_ref }}', '{{ target.name }}', current_timestamp());

        alter view {{ target.database }}.RISK_ANALYTICS_SCHEMA.VW_RESUMEN_UNIDAD_NEGOCIO
            set comment = 'Deployed by Azure DevOps build {{ build_id }} | commit {{ commit[:8] }} | ref {{ source_ref }}';
    {% endset %}
    {% do run_query(sql) %}
    {{ log("Deployment " ~ build_id ~ " (" ~ commit[:8] ~ ") logged in DEPLOYMENT_LOG", info=True) }}
{% endmacro %}
