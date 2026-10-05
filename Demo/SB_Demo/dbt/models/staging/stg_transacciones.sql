{{ config(materialized='view') }}

select
    trim(ID_TRANSACCION)             as ID_TRANSACCION,
    trim(ID_TARJETA)                 as ID_TARJETA,
    trim(RUT)                        as RUT,
    FECHA_TRANSACCION,
    MONTO,
    CATEGORIA,
    COMERCIO,
    CIUDAD,
    ESTADO,
    UNIDAD_NEGOCIO,
    CARGADO_EN
from {{ source('raw_banking', 'TRANSACCIONES') }}
