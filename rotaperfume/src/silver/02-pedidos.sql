CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.pedidos AS
SELECT
  CAST(pedido_id AS BIGINT) AS pedido_id,
  CAST(cliente_id AS BIGINT) AS cliente_id,
  CAST(vendedor_id AS BIGINT) AS vendedor_id,
  COALESCE(
    TRY_TO_DATE(data_pedido),
    TRY_TO_DATE(data_pedido, 'dd/MM/yyyy')
  ) AS data_pedido,
  TRIM(canal) AS canal,
  LOWER(TRIM(status)) AS status,
  CAST(valor_total AS DECIMAL(18, 2)) AS valor_total,
  CASE WHEN LOWER(TRIM(status)) = 'cancelado' THEN TRUE ELSE FALSE END AS cancelado,
  CASE
    WHEN LOWER(TRIM(status)) = 'cancelado' THEN CAST(0 AS DECIMAL(18, 2))
    ELSE CAST(valor_total AS DECIMAL(18, 2))
  END AS valor_liquido,
  YEAR(
    COALESCE(
      TRY_TO_DATE(data_pedido),
      TRY_TO_DATE(data_pedido, 'dd/MM/yyyy')
    )
  ) AS ano,
  MONTH(
    COALESCE(
      TRY_TO_DATE(data_pedido),
      TRY_TO_DATE(data_pedido, 'dd/MM/yyyy')
    )
  ) AS mes,
  CURRENT_TIMESTAMP() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.pedidos;

ALTER TABLE lakehouse_rotaperfume.silver.pedidos
  ADD CONSTRAINT pedidos_data_pedido_not_null CHECK (data_pedido IS NOT NULL);

ALTER TABLE lakehouse_rotaperfume.silver.pedidos
  ADD CONSTRAINT pedidos_cancelado_zero CHECK (NOT cancelado OR valor_liquido = 0);

COMMENT ON TABLE lakehouse_rotaperfume.silver.pedidos IS
  'Tabela silver de pedidos. Datas foram convertidas com TRY_TO_DATE para evitar falha em ANSI mode e pedidos cancelados foram sinalizados com coluna booleana, preservando o valor zerado sem mascarar a regra de negócio.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos.data_pedido IS
  'Data do pedido normalizada em ISO com coalescência de formatos dd/MM/yyyy e ISO.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos.valor_total IS
  'Valor bruto do pedido convertido de texto para DECIMAL(18,2) para permitir cálculos financeiros coerentes.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos.cancelado IS
  'Indicador de pedido cancelado derivado do status, usado para separar operação legítima de cancelamento sem gerar falsos positivos.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos.valor_liquido IS
  'Valor líquido do pedido: zero para cancelados e valor_total para pedidos vigentes, evitando que a regra de devolução afete o faturamento bruto.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos.ano IS
  'Ano derivado da data_pedido para facilitar segmentação temporal em dashboards e mineração.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos.mes IS
  'Mês derivado da data_pedido para permitir agregação por período sem depender de conversões frágeis.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos._processado_em IS
  'Timestamp de processamento da camada silver para auditoria e rastreabilidade.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos._linhas_origem IS
  'Indicador de linha processada na origem para visibilidade do volume de entrada.';
