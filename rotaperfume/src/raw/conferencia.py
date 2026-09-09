# Databricks notebook source
# ruff: noqa: F821

from datetime import datetime, timezone

from pyspark.sql import Row
from pyspark.sql.types import LongType, StringType, StructField, StructType, TimestampType

EXPECTED_FILES = {
    "erp": ("produtos", "pedidos", "itens_pedido", "pagamentos", "estoque"),
    "crm": ("clientes", "vendedores", "carteira", "oportunidades", "visitas"),
}


def expected_paths(catalog):
    return [
        (system, name, f"/Volumes/{catalog}/bronze/raw/{system}/{name}.csv")
        for system, names in EXPECTED_FILES.items()
        for name in names
    ]


def file_info(path):
    matches = dbutils.fs.ls(path)
    if not matches:
        raise FileNotFoundError(path)
    info = matches[0]
    if info.size == 0:
        raise ValueError(f"arquivo vazio: {path}")
    rows = spark.read.option("header", "true").option("inferSchema", "false").csv(path).count()
    if rows == 0:
        raise ValueError(f"arquivo sem linhas de dado: {path}")
    return info.size, rows


dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog")
records = []

for system, filename, path in expected_paths(catalog):
    try:
        size, rows = file_info(path)
    except Exception as error:
        raise RuntimeError(f"falha na conferência de {system}/{filename}.csv: {error}") from error
    records.append(Row(sistema=system, arquivo=f"{filename}.csv", bytes=size, linhas=rows))

if len(records) != 10:
    raise RuntimeError(f"manifesto incompleto: {len(records)} arquivos conferidos")

schema = StructType(
    [
        StructField("sistema", StringType(), False),
        StructField("arquivo", StringType(), False),
        StructField("bytes", LongType(), False),
        StructField("linhas", LongType(), False),
        StructField("conferido_em", TimestampType(), False),
    ]
)
checked_at = datetime.now(timezone.utc).replace(tzinfo=None)
rows = [Row(row.sistema, row.arquivo, row.bytes, row.linhas, checked_at) for row in records]
result = spark.createDataFrame(rows, schema=schema)
table_name = f"`{catalog}`.`bronze`.`_raw_arquivos`"
result.write.mode("overwrite").saveAsTable(table_name)
spark.sql(
    f"COMMENT ON TABLE {table_name} IS "
    "'Controle de chegada, tamanho e quantidade de linhas dos arquivos raw.'"
)

print("Conferência de chegada")
result.orderBy("sistema", "arquivo").show(20, truncate=False)