CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.vendedores AS
SELECT
  CAST(vendedor_id AS BIGINT) AS vendedor_id,
  TRIM(nome) AS nome,
  TRIM(regiao) AS regiao,
  TRIM(uf) AS uf,
  COALESCE(TRY_TO_DATE(data_admissao), TRY_TO_DATE(data_admissao, 'dd/MM/yyyy')) AS data_admissao,
  COALESCE(TRY_TO_DATE(data_desligamento), TRY_TO_DATE(data_desligamento, 'dd/MM/yyyy')) AS data_desligamento,
  CAST(meta_mensal AS DECIMAL(18, 2)) AS meta_mensal,
  CURRENT_TIMESTAMP() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.vendedores;

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.carteira AS
WITH base AS (
  SELECT
    CAST(carteira_id AS BIGINT) AS carteira_id,
    CAST(cliente_id AS BIGINT) AS cliente_id,
    CAST(vendedor_id AS BIGINT) AS vendedor_id,
    COALESCE(TRY_TO_DATE(data_inicio), TRY_TO_DATE(data_inicio, 'dd/MM/yyyy')) AS data_inicio,
    COALESCE(TRY_TO_DATE(data_fim), TRY_TO_DATE(data_fim, 'dd/MM/yyyy')) AS data_fim
  FROM lakehouse_rotaperfume.bronze.carteira
),
joined AS (
  SELECT
    b.*, v.data_desligamento
  FROM base b
  LEFT JOIN lakehouse_rotaperfume.silver.vendedores v
    ON v.vendedor_id = b.vendedor_id
)
SELECT
  carteira_id,
  cliente_id,
  vendedor_id,
  data_inicio,
  data_fim,
  CASE
    WHEN COALESCE(data_fim, DATE '2999-12-31') >= CURRENT_DATE
     AND COALESCE(data_desligamento, DATE '2999-12-31') >= CURRENT_DATE
    THEN TRUE
    ELSE FALSE
  END AS vigente,
  CASE
    WHEN COALESCE(data_fim, DATE '2999-12-31') >= CURRENT_DATE
     AND data_desligamento IS NOT NULL
     AND data_desligamento < CURRENT_DATE
    THEN TRUE
    ELSE FALSE
  END AS orfao_vendedor_desligado,
  CURRENT_TIMESTAMP() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM joined;

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.oportunidades AS
SELECT
  CAST(oportunidade_id AS BIGINT) AS oportunidade_id,
  CAST(cliente_id AS BIGINT) AS cliente_id,
  CAST(vendedor_id AS BIGINT) AS vendedor_id,
  TRIM(origem) AS origem,
  COALESCE(TRY_TO_DATE(data_abertura), TRY_TO_DATE(data_abertura, 'dd/MM/yyyy')) AS data_abertura,
  CASE
    WHEN LOWER(TRIM(etapa)) = 'fechado ganho' THEN 'ganho'
    WHEN LOWER(TRIM(etapa)) = 'fechado perdido' THEN 'perdido'
    ELSE LOWER(TRIM(etapa))
  END AS etapa,
  CAST(probabilidade_pct AS INT) AS probabilidade_pct,
  CAST(valor_estimado AS DECIMAL(18, 2)) AS valor_estimado,
  COALESCE(TRY_TO_DATE(data_fechamento), TRY_TO_DATE(data_fechamento, 'dd/MM/yyyy')) AS data_fechamento,
  CAST(ciclo_dias AS INT) AS ciclo_dias,
  TRIM(motivo_perda) AS motivo_perda,
  CURRENT_TIMESTAMP() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.oportunidades;

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.visitas AS
SELECT
  CAST(visita_id AS BIGINT) AS visita_id,
  CAST(cliente_id AS BIGINT) AS cliente_id,
  CAST(vendedor_id AS BIGINT) AS vendedor_id,
  COALESCE(TRY_TO_DATE(data_visita), TRY_TO_DATE(data_visita, 'dd/MM/yyyy')) AS data_visita,
  TRIM(resultado) AS resultado,
  CAST(duracao_min AS INT) AS duracao_min,
  CURRENT_TIMESTAMP() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.visitas;

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.pagamentos AS
SELECT
  CAST(pagamento_id AS BIGINT) AS pagamento_id,
  CAST(pedido_id AS BIGINT) AS pedido_id,
  TRIM(forma_pagamento) AS forma_pagamento,
  CAST(parcelas AS INT) AS parcelas,
  CAST(valor AS DECIMAL(18, 2)) AS valor,
  CAST(taxa_pct AS DECIMAL(18, 2)) AS taxa_pct,
  CAST(valor_liquido AS DECIMAL(18, 2)) AS valor_liquido,
  COALESCE(TRY_TO_DATE(data_vencimento), TRY_TO_DATE(data_vencimento, 'dd/MM/yyyy')) AS data_vencimento,
  COALESCE(TRY_TO_DATE(data_pagamento), TRY_TO_DATE(data_pagamento, 'dd/MM/yyyy')) AS data_pagamento,
  TRIM(status_pagamento) AS status_pagamento,
  CURRENT_TIMESTAMP() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.pagamentos;

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.estoque AS
SELECT
  COALESCE(TRY_TO_DATE(data_snapshot), TRY_TO_DATE(data_snapshot, 'dd/MM/yyyy')) AS data_snapshot,
  TRIM(sku) AS sku,
  CAST(saldo AS INT) AS saldo,
  CASE WHEN CAST(saldo AS INT) = 0 THEN TRUE ELSE FALSE END AS ruptura,
  CURRENT_TIMESTAMP() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.estoque;

COMMENT ON TABLE lakehouse_rotaperfume.silver.vendedores IS
  'Tabela silver de vendedores. Datas de admissão e desligamento foram normalizadas com TRY_TO_DATE e campos monetários convertidos para tipos numéricos.';

COMMENT ON TABLE lakehouse_rotaperfume.silver.carteira IS
  'Tabela silver de carteira. O cálculo de vigente e orfao_vendedor_desligado preserva a linha problemática para gestão, sem corrigir a origem.';

COMMENT ON TABLE lakehouse_rotaperfume.silver.oportunidades IS
  'Tabela silver de oportunidades com etapas padronizadas para evitar inconsistência entre Fechado ganho/Fechado perdido e rótulos de análise.';

COMMENT ON TABLE lakehouse_rotaperfume.silver.visitas IS
  'Tabela silver de visitas com datas e durações tipadas para facilitar análise de conversão e comportamento de vendedores.';

COMMENT ON TABLE lakehouse_rotaperfume.silver.pagamentos IS
  'Tabela silver de pagamentos com conversão de datas e valores para permitir reconciliamento financeiro e análise de atraso.';

COMMENT ON TABLE lakehouse_rotaperfume.silver.estoque IS
  'Tabela silver de estoque com saldo tipado e ruptura derivada em booleano para representar indisponibilidade do SKU.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.carteira.vigente IS
  'Indicador de carteira vigente que respeita data_fim e a data_desligamento do vendedor para sinalizar a vigência real do relacionamento.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.carteira.orfao_vendedor_desligado IS
  'Campo de exposição do problema: carteira ainda ativa para vendedor desligado, preservando a anomalia para gestão tomar a decisão correta.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.oportunidades.etapa IS
  'Etapa normalizada a partir dos valores da origem: Fechado ganho e Fechado perdido foram mapeados em ganho e perdido, sem confundir com rótulos divergentes.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.estoque.ruptura IS
  'Indicador de ruptura do SKU definido por saldo igual a zero, para facilitar monitoramento de disponibilidade.';
