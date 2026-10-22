-- C05 CI/CD demo artifact: official KPI view per business unit.
-- Built on the governed fact, so masking and RLS_BUSINESS_UNIT still apply
-- to whoever queries the view.
select
    UNIDAD_NEGOCIO,
    count(*)                                                   as QTD_TRANSACCIONES,
    count_if(ESTADO = 'RECHAZADA')                             as QTD_RECHAZADAS,
    round(div0(count_if(ESTADO = 'RECHAZADA'), count(*)), 4)   as TASA_RECHAZO,
    sum(MONTO)                                                 as MONTO_TOTAL
from {{ ref('credit_card_transactions') }}
group by UNIDAD_NEGOCIO
