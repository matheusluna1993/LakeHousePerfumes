-- Testes bloqueantes da camada Gold. Cada falha interrompe a tarefa.
WITH metricas AS (
  SELECT
    (SELECT ROUND(SUM(receita), 2) FROM lakehouse_rotaperfume.gold.fato_vendas) AS receita_gold,
    (SELECT ROUND(SUM(valor_liquido), 2) FROM lakehouse_rotaperfume.silver.pedidos) AS receita_silver,
    (SELECT COUNT(*) - COUNT(DISTINCT cnpj) FROM lakehouse_rotaperfume.silver.clientes) AS cnpj_duplicados,
    (SELECT COUNT(*) FROM lakehouse_rotaperfume.silver.pedidos WHERE data_pedido IS NULL) AS pedidos_sem_data,
    (SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.fato_vendas WHERE receita < 0 AND NOT devolucao) AS negativas_sem_devolucao,
    (SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.fato_vendas) AS linhas_fato,
    (SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.fato_vendas f LEFT ANTI JOIN lakehouse_rotaperfume.silver.pedidos p ON p.pedido_id = f.pedido_id) AS pedidos_orfaos,
    (SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.fato_vendas f LEFT ANTI JOIN lakehouse_rotaperfume.silver.clientes c ON c.cliente_id = f.cliente_id) AS clientes_orfaos,
    (SELECT ROUND(SUM(receita), 2) FROM lakehouse_rotaperfume.gold.mart_produto_performance) AS receita_mart_produto,
    (SELECT ROUND(SUM(receita), 2) FROM lakehouse_rotaperfume.gold.fato_vendas) AS receita_fato,
    (SELECT COUNT(*) FROM lakehouse_rotaperfume.silver.clientes WHERE LENGTH(cnpj) <> 14) AS cnpjs_invalidos
)
SELECT
  teste,
  CAST(valor_calculado AS STRING) AS valor_calculado,
  CAST(valor_esperado AS STRING) AS valor_esperado,
  CASE WHEN passou THEN 'PASSOU' ELSE raise_error(mensagem) END AS status
FROM (
  SELECT '1 - receita Gold igual Silver' AS teste, CAST(receita_gold AS STRING) AS valor_calculado, CAST(receita_silver AS STRING) AS valor_esperado,
    ABS(receita_gold - receita_silver) <= 0.01 AS passou, 'receita da Gold diferente da Silver' AS mensagem FROM metricas
  UNION ALL
  SELECT '2 - CNPJ unico', CAST(cnpj_duplicados AS STRING), CAST(0 AS STRING), cnpj_duplicados = 0, 'CNPJ duplicado na Silver' FROM metricas
  UNION ALL
  SELECT '3 - data de pedido preenchida', CAST(pedidos_sem_data AS STRING), CAST(0 AS STRING), pedidos_sem_data = 0, 'data_pedido nula na Silver' FROM metricas
  UNION ALL
  SELECT '4 - receita negativa somente devolucao', CAST(negativas_sem_devolucao AS STRING), CAST(0 AS STRING), negativas_sem_devolucao = 0, 'receita negativa sem flag de devolucao' FROM metricas
  UNION ALL
  SELECT '5 - volume do fato', CAST(linhas_fato AS STRING), '140000 a 250000', linhas_fato BETWEEN 140000 AND 250000, 'volume do fato fora do intervalo esperado' FROM metricas
  UNION ALL
  SELECT '6 - pedidos referenciados', CAST(pedidos_orfaos AS STRING), CAST(0 AS STRING), pedidos_orfaos = 0, 'pedido_id sem correspondencia na Silver' FROM metricas
  UNION ALL
  SELECT '7 - clientes referenciados', CAST(clientes_orfaos AS STRING), CAST(0 AS STRING), clientes_orfaos = 0, 'cliente_id sem correspondencia na Silver' FROM metricas
  UNION ALL
  SELECT '8 - mart de produto fecha com fato', CAST(receita_mart_produto AS STRING), CAST(receita_fato AS STRING), ABS(receita_mart_produto - receita_fato) <= 0.01, 'mart de produto nao fecha com o fato' FROM metricas
  UNION ALL
  SELECT '9 - CNPJ com 14 digitos', CAST(cnpjs_invalidos AS STRING), CAST(0 AS STRING), cnpjs_invalidos = 0, 'CNPJ fora de 14 digitos' FROM metricas
) testes;
