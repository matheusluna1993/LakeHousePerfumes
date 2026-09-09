-- CONTRATO DO FATO
-- Granularidade: uma linha por ITEM de pedido.
-- Filtro: pedidos cancelados sao excluidos; devolucoes permanecem no fato.
-- Devolucoes conservam quantidade, receita, custo e margem com sinal negativo.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.fato_vendas
PARTITIONED BY (ano, mes)
AS
SELECT
  p.pedido_id,
  i.item_id,
  p.data_pedido,
  p.ano,
  p.mes,
  p.canal,
  p.cliente_id,
  c.razao_social,
  c.segmento,
  c.cidade,
  p.vendedor_id,
  i.sku,
  pr.categoria,
  pr.marca,
  pr.nota_olfativa,
  i.quantidade,
  i.preco_praticado,
  CAST(i.quantidade * i.preco_praticado AS DECIMAL(18, 2)) AS receita,
  CAST(i.quantidade * pr.custo_unitario AS DECIMAL(18, 2)) AS custo,
  CAST(i.quantidade * (i.preco_praticado - pr.custo_unitario) AS DECIMAL(18, 2)) AS margem,
  i.devolucao
FROM lakehouse_rotaperfume.silver.pedidos p
JOIN lakehouse_rotaperfume.silver.itens_pedido i ON i.pedido_id = p.pedido_id
LEFT JOIN lakehouse_rotaperfume.silver.produtos pr ON pr.sku = i.sku
LEFT JOIN lakehouse_rotaperfume.silver.clientes c ON c.cliente_id = p.cliente_id
WHERE NOT p.cancelado;

COMMENT ON TABLE lakehouse_rotaperfume.gold.fato_vendas IS
  'Fato de vendas no grao de item de pedido. Exclui cancelamentos e preserva devolucoes para que a receita liquida seja reconciliavel com a Silver.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.receita IS
  'Valor comercial do item, calculado como quantidade vezes preco praticado; devolucoes ficam negativas.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.custo IS
  'Custo do produto no item, calculado como quantidade vezes custo unitario; acompanha o sinal da devolucao.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.margem IS
  'Receita menos custo do produto. Nao considera desconto comercial nem frete.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.devolucao IS
  'Indica que o item foi devolvido; a quantidade e as metricas financeiras permanecem negativas para refletir o estorno.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.quantidade IS
  'Quantidade comercializada no item; valores negativos representam devolucoes.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.preco_praticado IS
  'Preco unitario efetivamente registrado no item do pedido.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.data_pedido IS
  'Data comercial usada para atribuir o item ao periodo de venda.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.canal IS
  'Canal comercial informado no pedido.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.cliente_id IS
  'Identificador do cliente responsavel pela compra.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.vendedor_id IS
  'Identificador do vendedor associado ao pedido.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.sku IS
  'Codigo do SKU comercializado no item.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.pedido_id IS
  'Identificador do pedido que originou o item comercial.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.item_id IS
  'Identificador unico da linha de item no pedido.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.ano IS
  'Ano derivado da data do pedido para particionamento e analise temporal.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.mes IS
  'Mes derivado da data do pedido para particionamento e analise temporal.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.razao_social IS
  'Razao social do cliente associado ao pedido.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.segmento IS
  'Segmento comercial do cliente associado ao pedido.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.cidade IS
  'Cidade do cliente associado ao pedido.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.categoria IS
  'Categoria comercial do produto vendido.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.marca IS
  'Marca comercial do produto vendido.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.nota_olfativa IS
  'Nota olfativa cadastrada para o produto vendido.';
