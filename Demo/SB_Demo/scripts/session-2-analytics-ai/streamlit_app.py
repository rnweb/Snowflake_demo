"""Panel de Prevención de Fraude — aplicación Streamlit (Session 2).

Interfaz en español para la demo de la Superintendencia de Bancos:

1. KPIs y gráficos de la franquicia de tarjetas de crédito (mart de Core)
2. Formulario de evaluación de riesgo que invoca el modelo registrado
   SUPERINTENDENCY_DEMO_DB.RISK_ANALYTICS_SCHEMA.DETECTOR_FRAUDES (V1)
   mediante SQL:  SELECT MODEL(..., V1)!predict(...) FROM (SELECT 1)
3. Caja de texto con funciones de Cortex (AI_SUMMARIZE) — se muestra un
   aviso amable si la función no está disponible en la cuenta.

Conexión: en Streamlit in Snowflake se usa la sesión activa
(snowflake.snowpark.context.get_active_session); en desarrollo local se
recurre a st.connection("snowflake"). La sesión se cambia a
FR_DATA_ENGINEER de forma vigilada, con repuesto al rol de despliegue.

Diseño defensivo (para el ensayo general): cada sección se ejecuta bajo
try/except y los tipos se normalizan explícitamente (str/float) antes de
llegar a los elementos de Streamlit, de modo que un fallo puntual se
muestra como mensaje en lugar de tumbar la aplicación completa.
Sin plotly: gráficos nativos de Streamlit (bar_chart/line_chart).

IMPORTANTE (guardrail): esta app NO se despliega desde la automatización.
Requiere revisión humana y aprobación explícita antes del CREATE STREAMLIT
(ver Demo/SB_Demo/scripts/session-2-analytics-ai/README.md).
"""

import json

import pandas as pd
import streamlit as st

DB = "SUPERINTENDENCY_DEMO_DB"
MART = f"{DB}.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS"
MODEL_NAME = "DETECTOR_FRAUDES"
MODEL_VERSION = "V1"
REGISTRY_SCHEMA = "RISK_ANALYTICS_SCHEMA"

st.set_page_config(
    page_title="Panel de Prevención de Fraude",
    layout="wide",
    initial_sidebar_state="expanded",
)


@st.cache_resource(show_spinner=False)
def get_session():
    """Sesión Snowflake de la aplicación (SIS: sesión activa; local: conexión)."""
    try:
        from snowflake.snowpark.context import get_active_session

        session = get_active_session()
    except Exception:
        conn = st.connection("snowflake")
        session = conn.session()
    try:
        session.use_role("FR_DATA_ENGINEER")
    except Exception:
        # El rol de despliegue ya dispone de los privilegios necesarios.
        pass
    return session


def _clean(df: pd.DataFrame) -> pd.DataFrame:
    """Normaliza tipos antes de los elementos (compatibilidad SIS).

    Columnas a str, Decimal a float, date/Timestamp a str — el motor de
    protobuf de SIS rechaza tipos no primitivos con un TypeError opaco.
    """
    df = df.copy()
    df.columns = [str(c) for c in df.columns]
    for col in df.columns:
        if str(df[col].dtype).startswith("datetime"):
            df[col] = df[col].astype(str)
        elif df[col].dtype == object:
            muestra = df[col].dropna().head(1)
            if len(muestra):
                tipo = type(muestra.iloc[0]).__name__
                if tipo == "Decimal":
                    df[col] = df[col].astype("float64")
                elif tipo in ("date", "datetime", "Timestamp"):
                    df[col] = df[col].astype(str)
    return df


def _entero(valor) -> int:
    """int null-safe: None/NaN/no numérico -> 0 (no revienta los KPIs)."""
    try:
        if valor is None or valor != valor:
            return 0
        return int(valor)
    except (TypeError, ValueError):
        return 0


@st.cache_data(ttl=300, show_spinner="Cargando datos de la franquicia...")
def run_query(sql: str) -> pd.DataFrame:
    return _clean(get_session().sql(sql).to_pandas())


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
    col1.metric("Transacciones", f"{_entero(df['TRANSACCIONES']):,}".replace(",", "."))
    col2.metric("Monto total", f"${_entero(df['MONTO_TOTAL']):,}".replace(",", "."))
    col3.metric("Rechazadas", f"{_entero(df['RECHAZADAS']):,}".replace(",", "."))
    col4.metric("Alertas de riesgo", f"{_entero(df['ALERTAS']):,}".replace(",", "."))


def graficos() -> None:
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
    st.bar_chart(df_cat, x="CATEGORIA", y="MONTO_TOTAL", use_container_width=True)

    st.subheader("Distribución por estado")
    df_est = run_query(
        f"""
        SELECT ESTADO, COUNT(*) AS OPERACIONES
        FROM {MART}
        GROUP BY ESTADO
        ORDER BY OPERACIONES DESC
        """
    )
    st.bar_chart(df_est, x="ESTADO", y="OPERACIONES", use_container_width=True)

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
    st.line_chart(df_mes, x="MES", y="MONTO_TOTAL", use_container_width=True)


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
            crudo = get_session().sql(sql).collect()[0][0]
            payload = json.loads(crudo) if isinstance(crudo, str) else dict(crudo)
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
                f"SELECT AI_SUMMARIZE({literal})"
            ).collect()[0][0]
            st.info(str(resumen))
        except Exception as exc:  # noqa: BLE001
            if "399258" in str(exc) or "399270" in str(exc):
                st.warning(
                    "Las funciones de IA de Cortex no están disponibles en "
                    "esta cuenta (puerta de licencia o funciones heredadas "
                    "bloqueadas en cuentas nuevas). Con una cuenta habilitada, "
                    "esta caja genera resúmenes en español con AI_SUMMARIZE."
                )
            else:
                st.error(f"Error al invocar Cortex: {exc}")


def _seccion(nombre: str, funcion) -> None:
    try:
        funcion()
    except Exception as exc:  # noqa: BLE001 - resiliencia del ensayo general
        st.error(f"La sección «{nombre}» no está disponible: {exc}")


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
              (50.000.000 transacciones sintéticas)
            - **Modelo**: `DETECTOR_FRAUDES` (RandomForest, V1)
            - **Rol**: `FR_DATA_ENGINEER` (con repuesto al rol de despliegue)
            - **Almacén**: `WH_APP_MEDIUM`
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

    _seccion("KPIs de la franquicia", kpis)
    st.divider()
    _seccion("Gráficos", graficos)
    st.divider()
    _seccion("Transacciones prioritarias", tabla_alertas)
    st.divider()
    _seccion("Evaluación de riesgo", evaluador_riesgo)
    st.divider()
    _seccion("Resumen con Cortex", caja_cortex)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001 — traza visible en la UI, nunca pantalla en blanco
        st.exception(e)
