CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.produtos AS
SELECT
  TRIM(sku) AS sku,
  TRIM(descricao) AS descricao,
  TRIM(categoria) AS categoria,
  TRIM(marca) AS marca,
  TRIM(nota_olfativa) AS nota_olfativa,
  CAST(preco_tabela AS DECIMAL(18, 2)) AS preco_tabela,
  CAST(custo_unitario AS DECIMAL(18, 2)) AS custo_unitario,
  TRIM(unidade) AS unidade,
  CASE WHEN LOWER(TRIM(ativo)) IN ('s', 'sim', 'true', '1', 'y') THEN TRUE ELSE FALSE END AS ativo,
  COALESCE(TRY_TO_DATE(data_lancamento), TRY_TO_DATE(data_lancamento, 'dd/MM/yyyy')) AS data_lancamento,
  CURRENT_TIMESTAMP() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.produtos;

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.itens_pedido AS
WITH base AS (
  SELECT
    CAST(item_id AS BIGINT) AS item_id,
    CAST(pedido_id AS BIGINT) AS pedido_id,
    TRIM(sku) AS sku,
    CAST(quantidade AS INT) AS quantidade,
    CAST(preco_praticado AS DECIMAL(18, 2)) AS preco_praticado,
    CAST(desconto_pct AS DECIMAL(18, 2)) AS desconto_pct,
    CAST(valor_bruto AS DECIMAL(18, 2)) AS valor_bruto
  FROM lakehouse_rotaperfume.bronze.itens_pedido
),
produto AS (
  SELECT
    b.*,
    p.ativo AS produto_ativo
  FROM base b
  LEFT JOIN lakehouse_rotaperfume.silver.produtos p
    ON p.sku = b.sku
)
SELECT
  item_id,
  pedido_id,
  sku,
  quantidade,
  CASE WHEN quantidade < 0 THEN TRUE ELSE FALSE END AS devolucao,
  ABS(quantidade) AS quantidade_abs,
  preco_praticado,
  desconto_pct,
  valor_bruto,
  CASE
    WHEN produto_ativo IS NULL OR produto_ativo = FALSE THEN TRUE ELSE FALSE
  END AS sku_descontinuado,
  CURRENT_TIMESTAMP() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM produto;

ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido
  ADD CONSTRAINT itens_pedido_quantidade_abs_positiva CHECK (quantidade_abs > 0);

COMMENT ON TABLE lakehouse_rotaperfume.silver.produtos IS
  'Tabela silver de produtos. Campos de precificação e status foram convertidos para tipos numéricos e booleanos para garantir análise consistente.';

COMMENT ON TABLE lakehouse_rotaperfume.silver.itens_pedido IS
  'Tabela silver de itens de pedido. Quantidades negativas são tratadas como devolução e não descartadas, preservando o histórico e permitindo análises de faturamento bruto e líquido sem perder o contexto do negócio.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.produtos.data_lancamento IS
  'Data de lançamento normalizada com TRY_TO_DATE para evitar falha em ANSI mode em valores em ISO ou vazios.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.produtos.ativo IS
  'Flag de status do produto convertida de S/N para booleano para uso em filtros e joins.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.itens_pedido.devolucao IS
  'Indicador de devolução derivado de quantidade negativa, uma regra de negócio e não de erro de ingestão.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.itens_pedido.quantidade_abs IS
  'Quantidade em módulo para manter o histórico de devolução sem perder o volume de itens no pedido.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.itens_pedido.sku_descontinuado IS
  'Bandera que sinaliza o SKU sem produto ativo na silver, preservando o histórico de itens mesmo quando o produto deixou de ser comercializado.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.itens_pedido._processado_em IS
  'Timestamp de processamento da camada silver para controle de pipeline e rastreabilidade.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.itens_pedido._linhas_origem IS
  'Indicador da linha processada na origem para manter visibilidade do volume de entrada.';
