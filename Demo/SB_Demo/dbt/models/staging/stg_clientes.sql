{{ config(materialized='view') }}

select
    trim(RUT)                        as RUT,
    trim(NOMBRE)                     as NOMBRE,
    trim(APELLIDO)                   as APELLIDO,
    FECHA_NACIMIENTO,
    SEXO,
    lower(trim(EMAIL))               as EMAIL,
    TELEFONO,
    CIUDAD,
    REGION,
    ESTADO,
    FECHA_ALTA,
    CARGADO_EN
from {{ source('raw_banking', 'CLIENTES') }}
