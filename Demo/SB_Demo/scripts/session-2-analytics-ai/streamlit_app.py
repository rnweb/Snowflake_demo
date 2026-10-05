"""Panel de Prevención de Fraude — aplicación Streamlit (Session 2).

Interfaz en español para la demo de la Superintendencia de Bancos:

1. KPIs y gráficos de la franquicia de tarjetas de crédito (mart de Core)
2. Formulario de evaluación de riesgo que invoca el modelo registrado
   SUPERINTENDENCY_DEMO_DB.RISK_ANALYTICS_SCHEMA.DETECTOR_FRAUDES (V1)
   mediante SQL:  SELECT MODEL(..., V1)!predict(...) FROM (SELECT 1)
3. Caja de texto con funciones de Cortex (SUMMARIZE) — requiere cuenta
   que no sea de prueba (trial); se muestra un aviso amable si no está
   disponible.

Conexión: st.connection("snowflake") (identidad de la aplicación desplegada);
la sesión se cambia a FR_DATA_ENGINEER de forma vigilada, con repuesto al
rol de despliegue si el cambio no está permitido.

IMPORTANTE (guardrail): esta app NO se despliega desde la automatización.
Requiere revisión humana y aprobación explícita antes del CREATE STREAMLIT
(ver scripts/session-2-analytics-ai/README.md).
"""

import json

import pandas as pd
import plotly.express as px
import streamlit as st

DB = "SUPERINTENDENCY_DEMO_DB"
MART = f"{DB}.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS"
MODEL_NAME = "DETECTOR_FRAUDES"
MODEL_VERSION = "V1"
REGISTRY_SCHEMA = "RISK_ANALYTICS_SCHEMA"

st.set_page_config(
    page_title="Panel de Prevención de Fraude",
    page_icon=None,
    layout="wide",
    initial_sidebar_state="expanded",
)


@st.cache_resource(show_spinner=False)
def get_session():
    """Sesión Snowflake de la aplicación (rol de despliegue -> ingeniero)."""
    conn = st.connection("snowflake")
    session = conn.session()
    try:
        session.use_role("FR_DATA_ENGINEER")
    except Exception:
        # El rol de despliegue ya dispone de los privilegios necesarios.
        pass
    return session


@st.cache_data(ttl=300, show_spinner="Cargando datos de la franquicia...")
def run_query(sql: str) -> pd.DataFrame:
    return get_session().sql(sql).to_pandas()


def kpis() -> None:
    df = run_query(
        f"""
        SELECT
            COUNT(*)                                             AS TRANSACCIONES,
            SUM(MONTO)                                           AS MONTO_TOTAL,
            SUM(CASE WHEN ESTADO = 'RECHAZADA' THEN 1 ELSE 0 END) AS RECHAZADAS,
            SUM(CASE
                    WHEN ESTADO = 'RECHAZADA' AND MONTO >= 250000 THEN 1
                    WHEN MONTO >= 400000 THEN 1
                    ELSE 0
                END)                                             AS ALERTAS
        FROM {MART}
        """
    ).iloc[0]
    col1, col2, col3, col4 = st.columns(4)
    col1.metric("Transacciones", f"{int(df['TRANSACCIONES']):,}".replace(",", "."))
    col2.metric("Monto total", f"${int(df['MONTO_TOTAL']):,}".replace(",", "."))
    col3.metric("Rechazadas", f"{int(df['RECHAZADAS']):,}".replace(",", "."))
    col4.metric("Alertas de riesgo", f"{int(df['ALERTAS']):,}".replace(",", "."))


def graficos() -> None:
    left, right = st.columns(2)

    with left:
        st.subheader("Monto por categoría")
        df_cat = run_query(
            f"""
            SELECT CATEGORIA,
                   SUM(MONTO) AS MONTO_TOTAL
            FROM {MART}
            GROUP BY CATEGORIA
            ORDER BY MONTO_TOTAL DESC
            """
        )
        fig = px.bar(
            df_cat,
            x="CATEGORIA",
            y="MONTO_TOTAL",
            labels={"CATEGORIA": "Categoría", "MONTO_TOTAL": "Monto total ($)"},
        )
        fig.update_layout(height=360, margin=dict(t=30, b=10))
        st.plotly_chart(fig, use_container_width=True)

    with right:
        st.subheader("Distribución por estado")
        df_est = run_query(
            f"""
            SELECT ESTADO, COUNT(*) AS OPERACIONES
            FROM {MART}
            GROUP BY ESTADO
            ORDER BY OPERACIONES DESC
            """
        )
        fig = px.pie(
            df_est,
            names="ESTADO",
            values="OPERACIONES",
            hole=0.45,
            labels={"ESTADO": "Estado"},
        )
        fig.update_layout(height=360, margin=dict(t=30, b=10))
        st.plotly_chart(fig, use_container_width=True)

    st.subheader("Evolución mensual del monto transado")
    df_mes = run_query(
        f"""
        SELECT DATE_TRUNC('MONTH', FECHA_TRANSACCION) AS MES,
               SUM(MONTO)                             AS MONTO_TOTAL
        FROM {MART}
        GROUP BY 1
        ORDER BY 1
        """
    )
    df_mes["MES"] = pd.to_datetime(df_mes["MES"]).dt.strftime("%Y-%m")
    fig = px.line(
        df_mes,
        x="MES",
        y="MONTO_TOTAL",
        markers=True,
        labels={"MES": "Mes", "MONTO_TOTAL": "Monto total ($)"},
    )
    fig.update_layout(height=320, margin=dict(t=30, b=10))
    st.plotly_chart(fig, use_container_width=True)


def tabla_alertas() -> None:
    st.subheader("Transacciones de mayor monto (revisión prioritaria)")
    df = run_query(
        f"""
        SELECT TOP 20
            FECHA_TRANSACCION,
            MONTO,
            CATEGORIA,
            COMERCIO,
            CIUDAD,
            ESTADO,
            UNIDAD_NEGOCIO
        FROM {MART}
        ORDER BY MONTO DESC
        """
    )
    st.dataframe(df, use_container_width=True, hide_index=True)
    st.caption(
        "Las columnas sensibles (RUT, número de tarjeta) no se muestran en la "
        "app; las políticas de enmascaramiento siguen aplicándose en consulta."
    )


def evaluador_riesgo() -> None:
    st.subheader("Evaluación de riesgo con el modelo DETECTOR_FRAUDES")
    st.caption(
        "El formulario invoca el modelo registrado en el Model Registry "
        "directamente desde SQL (V1)."
    )
    with st.form("form_riesgo"):
        c1, c2, c3 = st.columns(3)
        monto = c1.number_input(
            "Monto de la transacción ($)", 0, 10_000_000, 480_000, 10_000
        )
        hora = c2.slider("Hora del día", 0, 23, 2)
        dia = c3.selectbox(
            "Día de la semana (1=lunes)", list(range(1, 8)), index=5
        )
        c4, c5, c6 = st.columns(3)
        fin_semana = c4.checkbox("Fin de semana", value=True)
        categoria_riesgo = c5.checkbox("Categoría de alto riesgo", value=True)
        unidad = c6.selectbox(
            "Unidad de negocio", ["RETAIL (1)", "PYME (2)", "CORPORATIVO (3)"]
        )
        enviado = st.form_submit_button("Evaluar riesgo")

    if enviado:
        unidad_cod = int(unidad[-2])
        sql = f"""
        SELECT MODEL({DB}.{REGISTRY_SCHEMA}.{MODEL_NAME}, {MODEL_VERSION})!predict(
            MONTO => {monto},
            HORA => {hora},
            DIA_SEMANA => {dia},
            FIN_DE_SEMANA => {1 if fin_semana else 0},
            CATEGORIA_ALTO_RIESGO => {1 if categoria_riesgo else 0},
            UNIDAD_NEGOCIO_COD => {unidad_cod}
        ) AS PREDICCION
        FROM (SELECT 1 AS MUESTRA)
        """
        try:
            payload = json.loads(get_session().sql(sql).collect()[0][0])
            alerta = int(payload.get("PRED_ES_FRAUDE", 0)) == 1
        except Exception as exc:  # noqa: BLE001 - se muestra al presentador
            st.error(f"No fue posible invocar el modelo: {exc}")
            return
        if alerta:
            st.error(
                "ALERTA: el modelo clasifica esta transacción como "
                "potencialmente fraudulenta. Se recomienda revisión manual "
                "del caso."
            )
        else:
            st.success(
                "El modelo no detecta indicadores de fraude en esta "
                "transacción."
            )


def caja_cortex() -> None:
    st.subheader("Resumen inteligente con Snowflake Cortex")
    with st.form("form_cortex"):
        texto = st.text_area(
            "Texto a resumir",
            value=(
                "La Superintendencia de Bancos detectó transacciones "
                "sospechosas en la unidad de negocios Retail. Se recomienda "
                "revisar los pagos por encima de 400.000 pesos realizados "
                "fuera del horario habitual y verificar las transferencias "
                "repetidas de clientes corporativos."
            ),
            height=140,
        )
        resumir = st.form_submit_button("Generar resumen")
    if resumir:
        try:
            literal = "'" + texto.replace("'", "''") + "'"
            resumen = get_session().sql(
                f"SELECT SNOWFLAKE.CORTEX.SUMMARIZE({literal})"
            ).collect()[0][0]
            st.info(resumen)
        except Exception as exc:  # noqa: BLE001
            if "399258" in str(exc):
                st.warning(
                    "Las funciones de IA de Cortex no están disponibles en "
                    "cuentas de prueba (trial). Con una cuenta estándar, esta "
                    "caja genera resúmenes en español con CORTEX.SUMMARIZE."
                )
            else:
                st.error(f"Error al invocar Cortex: {exc}")


def main() -> None:
    st.title("Panel de Prevención de Fraude")
    st.caption(
        "Superintendencia de Bancos — demo de plataforma Snowflake · "
        "datos sintéticos"
    )

    with st.sidebar:
        st.header("Contexto")
        st.markdown(
            """
            - **Datos**: mart `CREDIT_CARD_TRANSACTIONS`
              (18.000 transacciones sintéticas)
            - **Modelo**: `DETECTOR_FRAUDES` (RandomForest, V1)
            - **Rol**: `FR_DATA_ENGINEER` (con repuesto al rol de despliegue)
            - **Almacén**: `WH_APP_XSMALL`
            """
        )
        st.caption(
            "App generada en Session 2 — despliegue solo tras revisión y "
            "aprobación humana."
        )

    try:
        rol = get_session().sql("SELECT CURRENT_ROLE()").collect()[0][0]
        st.caption(f"Sesión activa: rol {rol}")
    except Exception as exc:  # noqa: BLE001
        st.error(f"No fue posible conectar con Snowflake: {exc}")
        st.stop()

    kpis()
    st.divider()
    graficos()
    st.divider()
    tabla_alertas()
    st.divider()
    evaluador_riesgo()
    st.divider()
    caja_cortex()


if __name__ == "__main__":
    main()
