CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.clientes AS
WITH base AS (
  SELECT
    CAST(cliente_id AS BIGINT) AS cliente_id,
    TRIM(cnpj) AS cnpj_raw,
    TRIM(razao_social) AS razao_social_raw,
    TRIM(segmento) AS segmento_raw,
    TRIM(cidade) AS cidade_raw,
    TRIM(uf) AS uf_raw,
    data_cadastro AS data_cadastro_raw,
    LOWER(TRIM(ativo)) AS ativo_raw
  FROM lakehouse_rotaperfume.bronze.clientes
),
normalizado AS (
  SELECT
    cliente_id,
    LPAD(REGEXP_REPLACE(TRIM(cnpj_raw), '[^0-9]', ''), 14, '0') AS cnpj,
    REGEXP_REPLACE(INITCAP(TRIM(razao_social_raw)), '\\s+', ' ') AS razao_social,
    NULLIF(TRIM(segmento_raw), '') AS segmento,
    NULLIF(TRIM(cidade_raw), '') AS cidade,
    NULLIF(TRIM(uf_raw), '') AS uf,
    COALESCE(
      TRY_TO_DATE(data_cadastro_raw),
      TRY_TO_DATE(data_cadastro_raw, 'dd/MM/yyyy')
    ) AS data_cadastro,
    CASE WHEN ativo_raw IN ('s', 'sim', 'true', '1', 'y') THEN TRUE ELSE FALSE END AS ativo
  FROM base
),
dedup AS (
  SELECT
    n.*, 
    COUNT(*) OVER (PARTITION BY n.cnpj) AS qtd_cadastros,
    COLLECT_SET(n.cliente_id) OVER (PARTITION BY n.cnpj) AS cliente_ids_cnpj,
    ROW_NUMBER() OVER (
      PARTITION BY n.cnpj
      ORDER BY n.data_cadastro NULLS LAST, n.cliente_id ASC
    ) AS rn
  FROM normalizado n
)
SELECT
  cliente_id,
  cnpj,
  razao_social,
  segmento,
  cidade,
  uf,
  data_cadastro,
  ativo,
  CASE
    WHEN qtd_cadastros > 1 THEN ARRAY_EXCEPT(cliente_ids_cnpj, ARRAY(cliente_id))
    ELSE NULL
  END AS cliente_ids_duplicados,
  CURRENT_TIMESTAMP() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM dedup
WHERE rn = 1;

ALTER TABLE lakehouse_rotaperfume.silver.clientes
  ADD CONSTRAINT clientes_cnpj_14 CHECK (length(cnpj) = 14);

ALTER TABLE lakehouse_rotaperfume.silver.clientes
  ADD CONSTRAINT clientes_data_cadastro_not_null CHECK (data_cadastro IS NOT NULL);

COMMENT ON TABLE lakehouse_rotaperfume.silver.clientes IS
  'Tabela silver de clientes normalizados. CNPJ foi padronizado para 14 dígitos, razão social foi normalizada e registros duplicados por CNPJ foram mantidos pelo cadastro mais antigo com rastreio dos IDs descartados.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.cnpj IS
  'CNPJ normalizado para 14 dígitos, sem pontuação e sem espaços, preservando zeros à esquerda.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.razao_social IS
  'Razão social padronizada com initcap e espaços colapsados para manter consistência textual.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.data_cadastro IS
  'Data de cadastro convertida com TRY_TO_DATE em coalescência de ISO e dd/MM/yyyy para evitar falha em ANSI mode.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.cliente_ids_duplicados IS
  'Lista dos cliente_id duplicados descartados na deduplicação por CNPJ para manter rastreabilidade dos pedidos antigos.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.ativo IS
  'Flag de ativo convertida de S/N para booleano para permitir filtros consistentes.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes._processado_em IS
  'Timestamp de processamento da camada silver para auditoria e controle de pipeline.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes._linhas_origem IS
  'Indicador de linha processada na origem para dar visibilidade do volume de entrada.';
