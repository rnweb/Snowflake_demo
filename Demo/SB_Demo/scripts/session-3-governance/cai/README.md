# CAI – Entrega automática do Data Marketplace (C08-AE-07 / AE-08)

Processos CAI que automatizam o ciclo de pedidos da coleção DCL-4, baseados no
CDMP REST Accelerator Pack (Informatica). Ficam no projeto `Rest Accelerator`.

| Processo | O que faz por execução |
|---|---|
| p_SB_MP_Atender | `GET orders?dataCollectionIds=<DCL-4>&status=APPROVED` → 1º pedido → SQL do bloco A do script 05 (stub) → `PUT orders/{{orderId}}/fulfill?deliveryTargetId=&comment=` |
| p_SB_MP_Revogar | `GET consumerAccess?status=PENDING_WITHDRAW` → 1º acesso → SQL do bloco C (stub) → `PUT consumerAccess/{{consumerAccessId}}/withdrawn` |

Lições aprendidas com o serviço de sistema "Execute Data Marketplace API" (ICSExecuteCDMPApi):
- Path Variable: caminho com `{{nome}}` + objectlist `DataMarketplacePathVariables/pathVariables{name,value}`.
- PUT exige `payload` (mesmo `{}`); sem ele o serviço devolve "Unexpected exception found".
- `deliveryTargetId` do fulfill = `requestedProvisionedTargetRef` do pedido.
- Processo com saída Whole payload aceita só um campo de saída.
- Passos de montagem de parâmetros ficam fora do ramo da decisão (dentro dele o import descartou o passo).

Regerar: `python3 build_atender.py <pasta_export_CDMP_Orders> p_SB_MP_Atender.zip` e
`python3 build_revogar.py p_SB_MP_Atender.zip p_SB_MP_Revogar.zip`.
Pendente: trocar o stub pelo passo Snowflake real (conta nova) e agendar a cada 5 min.
