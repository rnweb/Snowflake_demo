{{ config(
    materialized='incremental',
    unique_key='ID_TRANSACCION',
    on_schema_change='append_new_columns'
) }}

with transacciones as (

    select * from {{ ref('stg_transacciones') }}

),

tarjetas as (

    select
        ID_TARJETA,
        NUMERO_TARJETA
    from {{ ref('stg_tarjetas_credito') }}

)

select
    t.ID_TRANSACCION,
    t.RUT,
    t.ID_TARJETA,
    c.NUMERO_TARJETA,
    t.FECHA_TRANSACCION,
    t.MONTO,
    t.CATEGORIA,
    t.COMERCIO,
    t.CIUDAD,
    t.ESTADO,
    t.UNIDAD_NEGOCIO
from transacciones t
inner join tarjetas c on t.ID_TARJETA = c.ID_TARJETA

{% if is_incremental() %}
where t.FECHA_TRANSACCION > (
    select coalesce(max(FECHA_TRANSACCION), '1900-01-01 00:00:00'::timestamp_ntz)
    from {{ this }}
)
{% endif %}
