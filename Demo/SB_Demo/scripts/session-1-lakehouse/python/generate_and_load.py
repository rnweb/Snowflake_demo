"""Session 1 — synthetic banking data generation + raw ingestion.

Generates Spanish banking datasets (modeled on the official Snowflake
Quickstart schema: CUSTOMERS / CREDIT_CARDS / TRANSACTIONS), PUTs them to an
internal stage and runs COPY INTO the STAGING_SCHEMA raw tables.

Role: FR_DATA_ENGINEER | Warehouse: WH_INGESTION_XSMALL

Usage (from the repository root):
    python scripts/session-1-lakehouse/python/generate_and_load.py
"""

import csv
import random
import sys
import tempfile
from datetime import date, datetime, timedelta
from pathlib import Path

import snowflake.connector

SEED = 42
N_CLIENTES = 600
N_TRANSACCIONES = 18_000
START_TS = datetime(2025, 10, 1)
END_TS = datetime(2026, 9, 30)

NOMBRES = [
    "Andres", "Maria", "Juan", "Camila", "Pedro", "Lucia", "Diego", "Valentina",
    "Francisco", "Isidora", "Mauricio", "Fernanda", "Rodrigo", "Constanza",
    "Sebastian", "Antonia", "Jorge", "Paulina", "Ricardo", "Daniela",
]
APELLIDOS = [
    "Gonzalez", "Muñoz", "Rojas", "Diaz", "Contreras", "Silva", "Torres",
    "Sepulveda", "Morales", "Castillo", "Vargas", "Herrera", "Rivera", "Paredes",
    "Cabrera", "Fuentes", "Alvarado", "Quintana", "Vergara", "Salazar",
]
CIUDADES_REGION = [
    ("Santiago", "Metropolitana"), ("Valparaiso", "Valparaiso"),
    ("Concepcion", "Biobio"), ("La Serena", "Coquimbo"),
    ("Antofagasta", "Antofagasta"), ("Vina del Mar", "Valparaiso"),
    ("Temuco", "Araucania"), ("Rancagua", "O'Higgins"),
    ("Puerto Montt", "Los Lagos"), ("Chillan", "Nuble"),
]
TIPOS_TARJETA = ["ESTANDAR", "ORO", "PLATINO"]
ESTADOS_TARJETA = ["ACTIVA", "ACTIVA", "ACTIVA", "ACTIVA", "BLOQUEADA", "VENCIDA"]
UNIDADES_NEGOCIO = ["CORPORATIVO", "RETAIL", "PYME"]
ESTADOS_CLIENTE = ["ACTIVO"] * 9 + ["SUSPENDIDO", "BLOQUEADO"]
CATEGORIAS = [
    "SUPERMERCADO", "RESTAURANTE", "FARMACIA", "BENCINA", "ROPA",
    "VIAJES", "ELECTRONICA", "EDUCACION", "SALUD", "ENTRETENIMIENTO",
]
COMERCIOS = [
    "Jumbo", "Lider", "Santa Isabel", "Mercadona", "Rappi", "Uber", "Cencosud",
    "Falabella", "Paris", "Redbanc", "Cruz Verde", "Salcobrand", "ENAP",
    "CinemaColombus", "Libreria Nacional", "Paris Cencosud", "Zara", "H&M",
]
ESTADOS_TX = ["APROBADA"] * 85 + ["RECHAZADA"] * 10 + ["PENDIENTE"] * 5


def rut_valido(numero: int) -> str:
    """Chilean RUT with a correct mod-11 verification digit."""
    reverse = str(numero)[::-1]
    total, factor = 0, 2
    for ch in reverse:
        total += int(ch) * factor
        factor = 2 if factor == 7 else factor + 1
    resto = 11 - (total % 11)
    dv = "K" if resto == 11 else ("0" if resto == 10 else str(resto))
    body = f"{numero:,}".replace(",", ".")
    return f"{body}-{dv}"


def luhn_checksum(number_wo_check: str) -> int:
    total = 0
    for i, ch in enumerate(reversed(number_wo_check)):
        d = int(ch)
        if i % 2 == 0:
            d *= 2
            if d > 9:
                d -= 9
        total += d
    return (10 - (total % 10)) % 10


def numero_tarjeta(rng: random.Random) -> str:
    prefix = rng.choice(["411111", "550000", "371449"])
    digits = prefix + "".join(str(rng.randint(0, 9)) for _ in range(15 - len(prefix)))
    pan = digits + str(luhn_checksum(digits))
    return "-".join(pan[i : i + 4] for i in range(0, 16, 4))


def build_dataset() -> dict[str, list[dict]]:
    rng = random.Random(SEED)

    clientes = []
    for i in range(N_CLIENTES):
        rut = rut_valido(5_000_000 + i * 137 + rng.randint(0, 99))
        nombre, apellido = rng.choice(NOMBRES), rng.choice(APELLIDOS)
        ciudad, region = rng.choice(CIUDADES_REGION)
        nacimiento = date(1965, 1, 1) + timedelta(days=rng.randint(0, 365 * 45))
        alta = date(2023, 1, 1) + timedelta(days=rng.randint(0, 365 * 3))
        clientes.append({
            "RUT": rut,
            "NOMBRE": nombre,
            "APELLIDO": apellido,
            "FECHA_NACIMIENTO": nacimiento.isoformat(),
            "SEXO": rng.choice(["M", "F"]),
            "EMAIL": f"{nombre.lower()}.{apellido.lower()}{i}@ejemplo.cl".replace("ñ", "n"),
            "TELEFONO": f"+569{rng.randint(10000000, 99999999)}",
            "CIUDAD": ciudad,
            "REGION": region,
            "ESTADO": rng.choice(ESTADOS_CLIENTE),
            "FECHA_ALTA": alta.isoformat(),
        })

    tarjetas = []
    card_n = 0
    for cliente in clientes:
        for _ in range(1 + (1 if rng.random() < 0.55 else 0)):
            card_n += 1
            unidad = rng.choice(UNIDADES_NEGOCIO)
            emision = date(2024, 1, 1) + timedelta(days=rng.randint(0, 700))
            tarjetas.append({
                "ID_TARJETA": f"TC-{card_n:06d}",
                "RUT": cliente["RUT"],
                "NUMERO_TARJETA": numero_tarjeta(rng),
                "TIPO": rng.choice(TIPOS_TARJETA),
                "LIMITE_CREDITO": f"{rng.choice([300000, 500000, 800000, 1500000, 3000000]):.2f}",
                "FECHA_EMISION": emision.isoformat(),
                "FECHA_VENCIMIENTO": f"{emision.year + 4}-{emision.month:02d}-15",
                "ESTADO": rng.choice(ESTADOS_TARJETA),
                "UNIDAD_NEGOCIO": unidad,
            })

    # Keep a single unit per card so RLS by business unit stays coherent
    tarjeta_to_unidad = {t["ID_TARJETA"]: t["UNIDAD_NEGOCIO"] for t in tarjetas}
    tarjeta_to_rut = {t["ID_TARJETA"]: t["RUT"] for t in tarjetas}
    tarjetas_activas = [t["ID_TARJETA"] for t in tarjetas if t["ESTADO"] == "ACTIVA"]

    transacciones = []
    span = int((END_TS - START_TS).total_seconds())
    for i in range(N_TRANSACCIONES):
        id_tarjeta = rng.choice(tarjetas_activas)
        fecha = START_TS + timedelta(seconds=rng.randint(0, span))
        transacciones.append({
            "ID_TRANSACCION": f"TX-{i + 1:07d}",
            "ID_TARJETA": id_tarjeta,
            "RUT": tarjeta_to_rut[id_tarjeta],
            "FECHA_TRANSACCION": fecha.strftime("%Y-%m-%d %H:%M:%S"),
            "MONTO": f"{rng.uniform(1500, 500000):.2f}",
            "CATEGORIA": rng.choice(CATEGORIAS),
            "COMERCIO": rng.choice(COMERCIOS),
            "CIUDAD": rng.choice(CIUDADES_REGION)[0],
            "ESTADO": rng.choice(ESTADOS_TX),
            "UNIDAD_NEGOCIO": tarjeta_to_unidad[id_tarjeta],
        })

    return {
        "clientes": clientes,
        "tarjetas_credito": tarjetas,
        "transacciones": transacciones,
    }


def write_csvs(dataset: dict[str, list[dict]], out_dir: Path) -> dict[str, Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    paths = {}
    for table, rows in dataset.items():
        path = out_dir / f"{table}.csv"
        with path.open("w", newline="", encoding="utf-8") as fh:
            writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)
        paths[table] = path
    return paths


def run_sql_file(cursor, sql_path: Path) -> None:
    statements = [s.strip() for s in sql_path.read_text(encoding="utf-8").split(";") if s.strip()]
    for stmt in statements:
        cursor.execute(stmt)


def main() -> int:
    session_dir = Path(__file__).resolve().parents[1]
    sql_dir = session_dir / "sql"
    data_dir = session_dir / "data" / "generated"

    dataset = build_dataset()
    paths = write_csvs(dataset, data_dir)
    for name, path in paths.items():
        print(f"[1/4] generated {name:<16} {len(dataset[name]):>6} rows -> {path}")

    ctx = snowflake.connector.connect(
        account="RBGXIGI-UAC53151",
        user="OPERATIONS",
        private_key_file=r"C:\Users\rnweb\rsa_key.p8",
        authenticator="SNOWFLAKE_JWT",
        role="FR_DATA_ENGINEER",
        warehouse="WH_INGESTION_XSMALL",
        database="SUPERINTENDENCY_DEMO_DB",
        schema="STAGING_SCHEMA",
    )
    try:
        cursor = ctx.cursor()
        print(f"[2/4] connected as {cursor.execute('select current_role()').fetchone()[0]} "
              f"on {cursor.execute('select current_warehouse()').fetchone()[0]}")

        run_sql_file(cursor, sql_dir / "01_create_raw_tables.sql")
        print("[3/4] raw tables / file format / stage ready")

        for path in paths.values():
            cursor.execute(
                f"PUT file://{path.as_posix()} "
                "@SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.RAW_STAGE OVERWRITE=TRUE"
            )
        print("[4/4] CSVs PUT to @RAW_STAGE — running COPY INTO")

        run_sql_file(cursor, sql_dir / "02_load_raw_data.sql")

        for table in dataset:
            count = cursor.execute(
                f"select count(*) from SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.{table}"
            ).fetchone()[0]
            print(f"       STAGING_SCHEMA.{table:<18} {count:>6} rows")
        cursor.close()
    finally:
        ctx.close()
    print("Session 1 raw ingestion complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
