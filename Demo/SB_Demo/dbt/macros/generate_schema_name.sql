-- Use the model's configured schema verbatim (STAGING_SCHEMA /
-- CORE_BANKING_SCHEMA) instead of the default <target.schema>_<custom> prefix.
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
