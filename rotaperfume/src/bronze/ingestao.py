# Databricks notebook source
# ruff: noqa: F821

from pyspark.sql.functions import col, current_timestamp

EXPECTED_FILES = {
    "erp": ("produtos", "pedidos", "itens_pedido", "pagamentos", "estoque"),
    "crm": ("clientes", "vendedores", "carteira", "oportunidades", "visitas"),
}


def ingest_table(catalog, system, table_name):
    """Read one raw CSV as strings and add only ingestion metadata."""
    source_path = f"/Volumes/{catalog}/bronze/raw/{system}/{table_name}.csv"
    return (
        spark.read.option("header", "true")
        .option("inferSchema", "false")
        .option("multiLine", "false")
        .csv(source_path)
        .withColumn("_ingerido_em", current_timestamp())
        .withColumn("_arquivo_origem", col("_metadata.file_path"))
    )


def qualified_name(catalog, table_name):
    return f"`{catalog}`.`bronze`.`{table_name}`"


dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog")
control_name = qualified_name(catalog, "_raw_arquivos")
expected_counts = {
    row.arquivo: row.linhas for row in spark.table(control_name).select("arquivo", "linhas").collect()
}

pending_tables = []
count_rows = []
for system, table_names in EXPECTED_FILES.items():
    for table_name in table_names:
        csv_name = f"{table_name}.csv"
        if csv_name not in expected_counts:
            raise RuntimeError(f"arquivo não registrado na conferência raw: {csv_name}")
        data = ingest_table(catalog, system, table_name)
        actual_count = data.count()
        expected_count = expected_counts[csv_name]
        count_rows.append((system, table_name, actual_count, expected_count, actual_count == expected_count))
        pending_tables.append((system, table_name, data))

comparison_schema = "sistema string, tabela string, linhas_lidas long, linhas_arquivo long, bate boolean"
comparison = spark.createDataFrame(count_rows, comparison_schema)
comparison.orderBy("linhas_lidas", ascending=False).show(20, truncate=False)

if comparison.filter("NOT bate").count() > 0:
    mismatches = comparison.filter("NOT bate").collect()
    details = ", ".join(f"{row.tabela}: {row.linhas_lidas} != {row.linhas_arquivo}" for row in mismatches)
    raise RuntimeError(f"contagens divergentes na bronze: {details}")

for system, table_name, data in pending_tables:
    target = qualified_name(catalog, table_name)
    data.write.format("delta").mode("overwrite").option("overwriteSchema", "true").saveAsTable(target)
    spark.sql(f"COMMENT ON TABLE {target} IS 'Tabela bronze recebida do sistema {system.upper()}.'")

print("Ingestão bronze concluída")
comparison.orderBy("linhas_lidas", ascending=False).show(20, truncate=False)