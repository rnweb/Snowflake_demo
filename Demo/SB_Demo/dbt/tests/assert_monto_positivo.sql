-- Regulatory data-quality guardrail: every posted amount must be positive.
select
    ID_TRANSACCION,
    MONTO
from {{ ref('credit_card_transactions') }}
where MONTO <= 0
