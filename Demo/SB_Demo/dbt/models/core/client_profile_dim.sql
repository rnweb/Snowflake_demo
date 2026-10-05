{{ config(materialized='table') }}

with clientes as (

    select * from {{ ref('stg_clientes') }}

),

tarjetas as (

    select
        RUT,
        count(*)                          as TOTAL_TARJETAS,
        sum(LIMITE_CREDITO)               as LIMITE_CREDITO_TOTAL
    from {{ ref('stg_tarjetas_credito') }}
    group by RUT

),

gastos as (

    select
        RUT,
        count(*)                                                       as TOTAL_TRANSACCIONES,
        sum(case when ESTADO = 'APROBADA' then MONTO else 0 end)       as MONTO_TOTAL_GASTADO
    from {{ ref('stg_transacciones') }}
    group by RUT

)

select
    c.RUT,
    c.NOMBRE,
    c.APELLIDO,
    c.EMAIL,
    c.CIUDAD,
    c.REGION,
    c.FECHA_NACIMIENTO,
    datediff('year', c.FECHA_NACIMIENTO, current_date())   as EDAD,
    c.ESTADO                                               as ESTADO_CLIENTE,
    c.FECHA_ALTA,
    coalesce(t.TOTAL_TARJETAS, 0)                          as TOTAL_TARJETAS,
    coalesce(t.LIMITE_CREDITO_TOTAL, 0)                    as LIMITE_CREDITO_TOTAL,
    coalesce(g.TOTAL_TRANSACCIONES, 0)                     as TOTAL_TRANSACCIONES,
    coalesce(g.MONTO_TOTAL_GASTADO, 0)                     as MONTO_TOTAL_GASTADO,
    current_timestamp()                                    as FECHA_ACTUALIZACION
from clientes c
left join tarjetas t on c.RUT = t.RUT
left join gastos   g on c.RUT = g.RUT
