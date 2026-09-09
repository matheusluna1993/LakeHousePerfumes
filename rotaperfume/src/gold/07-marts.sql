-- Marts Gold derivados das mesmas regras do fato de vendas.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor AS
WITH agregado AS (
  SELECT
    vendedor_id,
    ano,
    mes,
    SUM(receita) AS receita,
    SUM(margem) AS margem,
    COUNT(DISTINCT cliente_id) AS clientes_atendidos,
    COUNT(DISTINCT pedido_id) AS pedidos,
    AVG(receita) AS ticket_medio
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY vendedor_id, ano, mes
)
SELECT
  a.vendedor_id,
  v.nome,
  v.regiao,
  a.ano,
  a.mes,
  a.receita,
  a.margem,
  v.meta_mensal AS meta,
  CASE WHEN COALESCE(v.meta_mensal, 0) = 0 THEN NULL ELSE a.receita / v.meta_mensal END AS atingimento,
  a.clientes_atendidos,
  a.pedidos,
  a.ticket_medio
FROM agregado a
LEFT JOIN lakehouse_rotaperfume.gold.dim_vendedor v ON v.vendedor_id = a.vendedor_id;

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor IS
  'Mart comercial no grao vendedor por mes, derivado do fato de vendas para acompanhamento de meta, carteira atendida e rentabilidade.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.mart_vendas_por_vendedor.atingimento IS
  'Razao entre receita liquida do vendedor no mes e sua meta mensal; nulo quando nao existe meta.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.mart_vendas_por_vendedor.ticket_medio IS
  'Receita liquida media por item agregado no recorte do vendedor e mes.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_produto_performance AS
WITH agregado AS (
  SELECT
    sku,
    ano,
    mes,
    SUM(receita) AS receita,
    SUM(margem) AS margem,
    SUM(quantidade) AS quantidade
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY sku, ano, mes
), acumulado AS (
  SELECT
    a.*,
    SUM(receita) OVER (PARTITION BY ano, mes ORDER BY receita DESC, sku ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS receita_acumulada,
    SUM(receita) OVER (PARTITION BY ano, mes) AS receita_total
  FROM agregado a
)
SELECT
  a.sku,
  p.marca,
  p.categoria,
  a.ano,
  a.mes,
  a.receita,
  a.margem,
  CASE WHEN a.receita = 0 THEN NULL ELSE a.margem / a.receita END AS margem_pct,
  a.quantidade,
  a.receita_acumulada,
  CASE
    WHEN a.receita_total = 0 THEN 'C'
    WHEN a.receita_acumulada / a.receita_total <= 0.80 THEN 'A'
    WHEN a.receita_acumulada / a.receita_total <= 0.95 THEN 'B'
    ELSE 'C'
  END AS curva_abc
FROM acumulado a
LEFT JOIN lakehouse_rotaperfume.gold.dim_produto p ON p.sku = a.sku;

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_produto_performance IS
  'Mart de produto no grao SKU por mes, com rentabilidade, quantidade e classificacao ABC por receita acumulada.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.mart_produto_performance.margem_pct IS
  'Percentual de margem calculado como margem dividida pela receita liquida do SKU no mes.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.mart_produto_performance.curva_abc IS
  'Classificacao de prioridade por receita acumulada no mes: A ate 80 por cento, B ate 95 por cento e C no restante.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento AS
SELECT
  YEAR(data_vencimento) AS ano,
  MONTH(data_vencimento) AS mes,
  DATE_TRUNC('MONTH', data_vencimento) AS mes_vencimento,
  SUM(valor) AS valor_a_receber,
  SUM(CASE WHEN LOWER(status_pagamento) IN ('pago', 'liquidado', 'recebido', 'paid') THEN valor_liquido ELSE 0 END) AS recebido,
  AVG(
    CASE
      WHEN LOWER(status_pagamento) IN ('pago', 'liquidado', 'recebido', 'paid')
       AND data_pagamento IS NOT NULL
      THEN GREATEST(DATEDIFF(data_pagamento, data_vencimento), 0)
    END
  ) AS atraso_medio_dias,
  SUM(valor - COALESCE(valor_liquido, 0)) AS custo_taxa
FROM lakehouse_rotaperfume.silver.pagamentos
GROUP BY YEAR(data_vencimento), MONTH(data_vencimento), DATE_TRUNC('MONTH', data_vencimento);

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento IS
  'Mart financeiro no grao mes de vencimento para conciliacao de valores a receber, recebimentos, atrasos e taxas.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.mart_financeiro_recebimento.recebido IS
  'Soma do valor liquido dos pagamentos cujo status indica liquidacao efetiva.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.mart_financeiro_recebimento.atraso_medio_dias IS
  'Media de dias entre vencimento e pagamento apenas para pagamentos liquidados, sem permitir atraso negativo.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.mart_financeiro_recebimento.custo_taxa IS
  'Diferenca entre o valor original e o valor liquido recebido, representando o custo de taxas.';
