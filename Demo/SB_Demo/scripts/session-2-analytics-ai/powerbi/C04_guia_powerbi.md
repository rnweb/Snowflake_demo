# C04 — Power BI: guia de montagem para a Sessão 2

Pré-requisito: `sql/06_capa_semantica_c04.sql` executado (view `VW_TRANSACCIONES_NEGOCIO`
e semantic view `SV_RIESGO_TARJETAS`). Conexão Snowflake do Power BI com o usuário
`DEMO_ANALYST` (role `FR_BI_ANALYST`, warehouse `WH_APP_MEDIUM`).

| Item | O que montar | Seção |
|---|---|---|
| C04-PRE-06 / C04-AE-04 | Modelo sobre a view com nomes de negócio | 1 |
| C04-PRE-04 / C04-AE-06 | Métrica oficial × improvisada; modelo endossado e reutilizado | 2 |
| C04-PRE-02 / C04-PRE-05 / C04-AE-05 | Workspace de consumo × sandbox de desenvolvimento | 3 |
| C04-AE-02 | Carga massiva + indicadores de desempenho e consumo | 4 |

---

## 1. Modelo semântico com nomes de negócio (C04-PRE-06, C04-AE-04)

1. Power BI Desktop → *Get data* → Snowflake → `SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.VW_TRANSACCIONES_NEGOCIO`
   em **DirectQuery**.
2. As colunas já chegam como "Unidad de Negocio", "Monto", "RUT Cliente" etc.
   Nada é renomeado no Power BI: o nome vem da plataforma.
3. **Descrições:** o conector do Snowflake **não** traz o `COMMENT` das colunas para o
   Power BI. Na demo, mostre os comentários no Snowsight (*Data → view → Columns*) ou
   no `DESCRIBE SEMANTIC VIEW`, e diga que, em produção, o catálogo do IDMC (CDGC)
   publica essas descrições para o usuário de negócio. É o ponto **parcial** do
   C04-AE-04: nomes herdados ✅, descrições pelo catálogo.

## 2. Métrica oficial × improvisada (C04-PRE-04, C04-AE-06)

No modelo do item 1, crie uma tabela de medidas `_Indicadores Oficiales` com:

```DAX
Transacciones = COUNTROWS ( VW_TRANSACCIONES_NEGOCIO )

Ticket Promedio =
-- DEFINICIÓN OFICIAL (= SV_RIESGO_TARJETAS.ticket_promedio): solo APROBADAS
DIVIDE (
    CALCULATE ( SUM ( VW_TRANSACCIONES_NEGOCIO[Monto] ), VW_TRANSACCIONES_NEGOCIO[Estado] = "APROBADA" ),
    CALCULATE ( COUNTROWS ( VW_TRANSACCIONES_NEGOCIO ), VW_TRANSACCIONES_NEGOCIO[Estado] = "APROBADA" )
)

% Rechazo =
DIVIDE (
    CALCULATE ( COUNTROWS ( VW_TRANSACCIONES_NEGOCIO ), VW_TRANSACCIONES_NEGOCIO[Estado] = "RECHAZADA" ),
    COUNTROWS ( VW_TRANSACCIONES_NEGOCIO )
)
```

Em cada medida, preencha **Description** com o texto do `COMMENT` da semantic view.

**A métrica em conflito (preparada para a demo):** o mesmo rótulo "Ticket Promedio"
com o significado da área Comercial (gasto aprovado por cliente):

```DAX
Ticket Promedio (Comercial) =
DIVIDE (
    CALCULATE ( SUM ( VW_TRANSACCIONES_NEGOCIO[Monto] ), VW_TRANSACCIONES_NEGOCIO[Estado] = "APROBADA" ),
    DISTINCTCOUNT ( VW_TRANSACCIONES_NEGOCIO[RUT Cliente] )   -- funciona sobre o RUT mascarado (pseudônimo determinístico)
)
```

Mostre as duas em **cartões lado a lado + tabela** por "Unidad de Negocio" (num gráfico
de colunas a escala esconde a oficial). A seção 5 do `06_capa_semantica_c04.sql` mostra a
mesma diferença no Snowflake (~72 000–75 600 vezes). Não use "média de todos os estados"
como contraste: no dado sintético a diferença é de centavos.

**Publicar e reutilizar (C04-AE-06):**
1. Publique o modelo como `SB_Modelo_Riesgo_Oficial` no workspace de consumo.
2. No Service: *Settings → Endorsement* → **Certified**. Se a opção estiver cinza,
   o admin do tenant não habilitou certificação (Admin portal → *Export and sharing
   settings → Certification*); como você é o admin do trial, habilite e se inclua.
   Plano B: **Promoted**, disponível para qualquer dono do modelo.
3. Crie um **segundo relatório** com *Get data → Power BI semantic models →
   SB_Modelo_Riesgo_Oficial* (live connection). As medidas oficiais aparecem
   prontas, sem recriar lógica: essa é a evidência do C04-AE-06.

**Discurso:** *"La definición oficial vive en un solo lugar: en la capa semántica de
Snowflake y en el modelo certificado de Power BI. Un reporte nuevo la reutiliza; nadie
reescribe la fórmula. Y si alguien improvisa su propio 'Ticket Promedio', la diferencia
queda en evidencia contra la versión certificada."*

## 3. Consumo × desenvolvimento (C04-PRE-02, C04-PRE-05, C04-AE-05)

**Restrição atual:** só existe 1 usuário com Pro (o seu, em trial). Para compartilhar
conteúdo, o segundo usuário também precisa de Pro (ou o workspace precisa estar numa
capacidade Premium/Fabric F64+). Caminhos, do mais garantido ao menos:

| Opção | Como | Observação |
|---|---|---|
| **A. 2º usuário com Pro trial** (recomendado) | Admin center → criar `consumidor.sb@<seu tenant>` → entrar com ele no app.powerbi.com → *Start free trial* (Pro, 60 dias) | Exige ser admin do tenant (no trial você é) e que o self-service trial esteja permitido (padrão) |
| B. Capacidade Fabric trial | Admin portal / *Start Fabric trial* → atribuir os 2 workspaces à capacidade trial | Confirmar no tenant se usuário Free consegue ver conteúdo na capacidade trial antes de depender disso |
| C. Plano B sem 2º usuário | Mostrar os papéis configurados (*Manage access*) + o "View as" do relatório; consumo × desenvolvimento demonstrado pelas personas do Snowflake | Fica **parcial** |

**Montagem (opção A):**
1. Workspace **`SB - Reportes`** (consumo): você = Admin; `consumidor.sb` = **Viewer**.
   Publique ali o relatório oficial.
2. Workspace **`SB - Sandbox`** (desenvolvimento): você = Admin/Member. O consumidor
   **não** tem acesso.
3. Demo:
   - Como `consumidor.sb` (janela anônima): vê o relatório; não tem *Edit*, nem *New
     report*, nem acesso ao Sandbox.
   - Como você (dev): no Sandbox, *New report* a partir do modelo certificado →
     dashboard novo em 1 minuto.

**Discurso:** *"El usuario de consumo solo visualiza lo publicado; el desarrollador
construye en un sandbox aislado, reutilizando el modelo certificado. Y en ambos casos
Snowflake sigue aplicando enmascaramiento y seguridad por fila según la identidad de la
conexión."*

## 4. Carga massiva + indicadores (C04-AE-02)

1. **Carga:** rode o mapping `mt_SB_Riesgo_por_Rubro` no IDMC (agrega os 50M → 33
   linhas) e mostre no Monitor: início, fim, linhas lidas e gravadas.
2. **Atualização no Power BI:** página "Riesgo por Rubro" → *View → Performance
   analyzer* → *Start recording* → *Refresh visuals*. Mostre o tempo de cada visual
   (DAX query × Direct query).
3. **Consumo no Snowflake** (Snowsight, como `FR_DEMO_ADMIN`):

```sql
-- Consultas que o Power BI acabou de enviar: tempo, bytes, warehouse
SELECT START_TIME, USER_NAME, WAREHOUSE_NAME,
       TOTAL_ELAPSED_TIME/1000 AS SEGUNDOS, BYTES_SCANNED/1e6 AS MB_LEIDOS,
       ROWS_PRODUCED, LEFT(QUERY_TEXT, 80) AS QUERY
FROM TABLE(SUPERINTENDENCY_DEMO_DB.INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER(
       USER_NAME => 'DEMO_ANALYST', RESULT_LIMIT => 50))
WHERE START_TIME > DATEADD('minute', -15, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC;

-- Créditos por warehouse nas últimas horas (ACCOUNT_USAGE atrasa até ~3 h;
-- na demo, use a janela do ensaio da manhã)
SELECT WAREHOUSE_NAME, SUM(CREDITS_USED) AS CREDITOS
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME > DATEADD('hour', -24, CURRENT_TIMESTAMP())
GROUP BY 1 ORDER BY 2 DESC;
```

**Discurso:** *"La carga masiva corre en IDMC con su propio cómputo; el tablero se
actualiza en segundos, y cada consulta que Power BI envía queda registrada con tiempo,
volumen leído y el warehouse que la ejecutó: rendimiento y consumo visibles, sin
herramientas adicionales."*
