{{ config(materialized='view') }}

select
    trim(ID_TARJETA)                 as ID_TARJETA,
    trim(RUT)                        as RUT,
    NUMERO_TARJETA,
    TIPO,
    LIMITE_CREDITO,
    FECHA_EMISION,
    FECHA_VENCIMIENTO,
    ESTADO,
    UNIDAD_NEGOCIO,
    CARGADO_EN
from {{ source('raw_banking', 'TARJETAS_CREDITO') }}
