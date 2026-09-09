-- Dimensoes conformadas da camada Gold.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_cliente AS
WITH pedidos_cliente AS (
  SELECT
    cliente_id,
    MIN(data_pedido) AS data_primeiro_pedido,
    MAX(data_pedido) AS data_ultimo_pedido,
    COUNT(DISTINCT pedido_id) AS total_pedidos,
    SUM(valor_liquido) AS receita_acumulada
  FROM lakehouse_rotaperfume.silver.pedidos
  WHERE NOT cancelado
  GROUP BY cliente_id
)
SELECT
  c.cliente_id,
  c.cnpj,
  c.razao_social,
  c.segmento,
  c.cidade,
  c.uf,
  c.data_cadastro,
  p.data_primeiro_pedido,
  p.data_ultimo_pedido,
  COALESCE(p.total_pedidos, 0) AS total_pedidos,
  COALESCE(p.receita_acumulada, CAST(0 AS DECIMAL(18, 2))) AS receita_acumulada,
  CASE
    WHEN p.data_ultimo_pedido IS NULL THEN NULL
    ELSE DATEDIFF(CURRENT_DATE(), p.data_ultimo_pedido)
  END AS dias_sem_comprar,
  c.ativo
FROM lakehouse_rotaperfume.silver.clientes c
LEFT JOIN pedidos_cliente p ON p.cliente_id = c.cliente_id;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_cliente IS
  'Dimensao conformada de clientes para analises comerciais, contendo perfil cadastral e historico consolidado de compras nao canceladas.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_cliente.dias_sem_comprar IS
  'Quantidade de dias desde a ultima compra nao cancelada ate a data atual; cliente sem compra fica sem valor.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_cliente.receita_acumulada IS
  'Receita liquida acumulada dos pedidos nao cancelados associados ao cliente.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_produto AS
SELECT
  sku,
  descricao,
  marca,
  categoria,
  nota_olfativa,
  custo_unitario,
  preco_tabela,
  data_lancamento,
  NOT ativo AS descontinuado
FROM lakehouse_rotaperfume.silver.produtos;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_produto IS
  'Dimensao conformada de produtos para analises de catalogo, precificacao, custo e desempenho por SKU.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_produto.descontinuado IS
  'Indica que o SKU nao esta ativo na Silver e, portanto, nao deve ser tratado como produto atualmente comercializado.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_vendedor AS
SELECT
  vendedor_id,
  nome,
  regiao,
  uf,
  data_admissao,
  data_desligamento,
  meta_mensal,
  data_desligamento IS NULL OR data_desligamento >= CURRENT_DATE() AS ativo
FROM lakehouse_rotaperfume.silver.vendedores;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_vendedor IS
  'Dimensao conformada de vendedores para acompanhamento de cobertura, metas e desempenho comercial.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_vendedor.ativo IS
  'Vendedor considerado ativo quando nao possui desligamento ou quando seu desligamento ainda nao ocorreu na data atual.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_calendario AS
WITH limites AS (
  SELECT
    DATE_TRUNC('MONTH', MIN(data_pedido)) AS primeiro_mes,
    LAST_DAY(MAX(data_pedido)) AS ultimo_dia
  FROM lakehouse_rotaperfume.silver.pedidos
), dias AS (
  SELECT EXPLODE(SEQUENCE(primeiro_mes, ultimo_dia, INTERVAL 1 DAY)) AS data
  FROM limites
)
SELECT
  data,
  YEAR(data) AS ano,
  MONTH(data) AS mes,
  CASE MONTH(data)
    WHEN 1 THEN 'Janeiro'
    WHEN 2 THEN 'Fevereiro'
    WHEN 3 THEN 'Marco'
    WHEN 4 THEN 'Abril'
    WHEN 5 THEN 'Maio'
    WHEN 6 THEN 'Junho'
    WHEN 7 THEN 'Julho'
    WHEN 8 THEN 'Agosto'
    WHEN 9 THEN 'Setembro'
    WHEN 10 THEN 'Outubro'
    WHEN 11 THEN 'Novembro'
    WHEN 12 THEN 'Dezembro'
  END AS nome_mes,
  QUARTER(data) AS trimestre,
  DATE_FORMAT(data, 'EEEE') AS dia_semana,
  MONTH(data) IN (4, 6, 10) AS mes_pico_setor
FROM dias;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_calendario IS
  'Calendario diario do periodo coberto pelos pedidos Silver, com atributos para agregacoes temporais e sazonalidade do setor.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_calendario.mes_pico_setor IS
  'Indica os meses de abril, junho e outubro, definidos como meses de pico comercial do setor.';
