Lakehouse RotaPerfume
Projeto construído durante a Jornada de Dados ao Vivo — uma imersão prática de engenharia de dados moderna com Databricks. O objetivo foi sair do zero e entregar, em cinco sessões consecutivas, um lakehouse completo com pipeline automatizado, modelagem dimensional e dashboard versionado.

O que é esta imersão
A Jornada de Dados ao Vivo é uma imersão intensiva que substitui a teoria abstrata por entrega real: a cada sessão, um deploy em produção. O fio condutor é um distribuidor fictício de perfumes B2B — a RotaPerfume — com dados de ERP e CRM gerados sinteticamente.

O percurso segue a arquitetura medallion (bronze → silver → gold), mas o ponto central não é a nomenclatura: é entender por que cada camada existe e o que acontece quando você pula uma delas.

O que foi construído
Sessão 1 — Infraestrutura como código
O catálogo inteiro virou código. Em vez de clicar em Create catalog → Create schema três vezes, o workspace nasce de um arquivo YAML e sobe em trinta segundos — igual para qualquer pessoa da equipe.

Databricks Asset Bundle com targets dev e prod
Catálogo lakehouse_rotaperfume com schemas bronze, silver e gold declarados em YAML
Volume bronze.raw para receber os CSVs das origens
Upload dos 10 arquivos (ERP + CRM) para o Volume via script
Primeira tarefa do pipeline: raw_conferencia, que conta as linhas de cada CSV e grava uma tabela de controle (bronze._raw_arquivos) — porque arquivo que não chega não dá erro, dá número menor
O aprendizado central: se o workspace sumir hoje, um databricks bundle deploy traz tudo de volta idêntico.

Sessão 2 — Bronze: o dado chega como veio
As 10 tabelas Delta da camada bronze — todas as colunas como texto, nenhuma conversão.

A decisão de não inferir tipos não é preguiça: é contrato. O Spark infere cliente_id e apaga os zeros à esquerda de 309 CNPJs. Ninguém recebe erro — o dado simplesmente some. A bronze preserva a sujeira de propósito, porque ela é a prova de que o problema veio da origem, não da pipeline.

inferSchema=False em todos os CSVs
Duas colunas de auditoria: _ingerido_em e _arquivo_origem
Validação automática contra bronze._raw_arquivos: se a contagem divergir, o job para
313.551 linhas ingeridas no total
Sessão 3 — Silver: limpeza com contrato
A camada mais trabalhosa — e a mais importante. Aqui ficam escritas as decisões de negócio que, sem documentação, viram "cada analista usa uma regra diferente".

Problemas encontrados e tratados:

Problema	Dado	Solução
CNPJ em 3 formatos diferentes	1.111 pontuados, 223 com espaço, 309 com zero à esquerda	trim + regexp_replace + lpad(14, '0')
40 CNPJs com dois cadastros	3.040 clientes → 3.000 únicos	row_number() por CNPJ, guardando IDs descartados em array
Datas em ISO e dd/MM/yyyy misturados	3.443 datas no formato brasileiro	coalesce(try_to_date(...), try_to_date(..., 'dd/MM/yyyy'))
Quantidade negativa em itens_pedido	2.327 devoluções	Coluna devolucao boolean — linha não é descartada
957 pedidos cancelados sem flag clara	Valor zero, sem marcação	Coluna cancelado boolean + valor_liquido zerado
A prova de que a limpeza está certa: a receita da silver tem que ser exatamente igual à da bronze. Nenhuma linha jogada fora. R$ 102.303.828,05 nas duas camadas.

Além da limpeza, cada tabela silver tem:

Constraints declaradas com ALTER TABLE ... ADD CONSTRAINT — a regra passa a ser da tabela, não de quem lembrou de escrever o IF
Colunas de auditoria _processado_em e _linhas_origem
COMMENT em todas as colunas que exigiram decisão de negócio
Sessão 4 — Gold: modelagem para consumo
A gold não é "a camada mais limpa" — isso é a silver. A gold é a camada modelada para um consumidor específico. Sem saber quem consome, não há como criar gold.

Fato central: fato_vendas com grão de item de pedido, excluindo pedidos cancelados mas mantendo devoluções com receita negativa e flag devolucao. Isso preserva os dois números que o negócio precisa: o bruto vendido e o líquido real.

Dimensões conformadas:

dim_cliente — enriquecida com métricas de compra calculadas a partir dos pedidos
dim_produto — com flag descontinuado como alias de NOT ativo
dim_vendedor — com meta mensal e status de atividade
dim_calendario — 24 meses gerados via sequence(), com mes_pico_setor marcando abril, junho e outubro
Marts analíticos — todos somam R$ 102.303.828,05 (conformados):

mart_vendas_por_vendedor — receita, margem, meta e atingimento por vendedor × mês
mart_produto_performance — receita e curva ABC por SKU × mês
mart_financeiro_recebimento — valor a receber, recebido e atraso médio por mês de vencimento
9 testes de qualidade com raise_error() — se qualquer um falhar, o job para antes de o dashboard atualizar. Dashboard com dado de ontem é melhor do que dashboard com dado errado de hoje.

Sessão 5 — Dashboard como código
O dashboard comercial versionado dentro do bundle: JSON no repositório, publicado junto com o deploy. Se alguém apagar o dashboard na interface, um deploy traz de volta idêntico.

Comparação direta: o dashboard da sessão 1 lia a bronze e precisava de dois try_to_date, um try_cast e uma regra de negócio solta no WHERE de cada query. O dashboard desta sessão lê a gold e usa SUM(receita).

Estrutura do projeto
lakehouse-perfumes/
├── dados/
│   ├── erp/          # produtos, pedidos, itens_pedido, pagamentos, estoque
│   └── crm/          # clientes, vendedores, visitas, oportunidades, carteira
└── rotaperfume/      # Databricks Asset Bundle
    ├── databricks.yml
    ├── resources/
    │   ├── pipeline.job.yml        # job com 10 tarefas em sequência e paralelo
    │   └── dashboard.dashboard.yml # dashboard Lakeview versionado
    ├── src/
    │   ├── bronze/   # Python: raw_conferencia.py, ingestao.py
    │   ├── silver/   # SQL: 01-clientes, 02-pedidos, 03-itens-e-produtos, 04-crm-e-financeiro
    │   └── gold/     # SQL: 05-dimensoes, 06-fato-vendas, 07-marts, 08-testes
    └── tests/        # testes com Databricks Connect
O pipeline executa nesta ordem — as tarefas silver rodam em paralelo entre si:

raw_conferencia → bronze_ingestao → silver_clientes ─┐
                                  → silver_pedidos    ├→ gold_dimensoes → gold_fato_vendas → gold_marts → testes
                                  → silver_itens_produtos ┤
                                  → silver_crm_financeiro ┘
Como reproduzir
# 1. instalar dependências
cd rotaperfume
uv sync --dev

# 2. autenticar no Databricks
databricks configure --profile jornadaaovivo

# 3. validar e fazer deploy
databricks bundle validate --profile jornadaaovivo
databricks bundle deploy --profile jornadaaovivo

# 4. executar o pipeline
databricks bundle run rotaperfume_pipeline --profile jornadaaovivo
O que isso agrega na carreira de engenheira de dados
Este projeto cobre, de forma aplicada, as práticas que separam engenharia de dados júnior de engenharia de dados sênior:

Infrastructure as Code para dados Criar catálogos e schemas clicando é rápido. Manter isso consistente entre dev, staging e produção — e conseguir recriar em dez minutos se o workspace sumir — é outra conversa. O projeto inteiro vive no Git e sobe com um comando.

Decisões de modelagem justificadas Cada escolha tem uma razão escrita: por que a bronze não converte tipos, por que a devolução fica dentro do fato com receita negativa, por que o constraint é NOT cancelado OR valor_liquido = 0 e não valor_liquido >= 0. Essas decisões aparecem em entrevistas e em code reviews.

Contratos de qualidade no dado, não no script Constraints Delta que recusam escrita inválida, testes com raise_error() que param o job, e comparação de receita entre camadas como critério de aceitação da limpeza. São as perguntas que qualquer time de dados maduro vai fazer.

Rastreabilidade de ponta a ponta Cada linha das tabelas bronze sabe de qual arquivo veio e quando entrou. A silver guarda os IDs descartados na deduplicação. O gold preserva devoluções com flag ao invés de removê-las. É possível responder "de onde veio esse número?" em qualquer camada.

Modelagem dimensional aplicada Dimensões conformadas, fato com grão explícito, marts com receita conformada entre si. Os conceitos do Kimball em prática, com a camada de teste provando que os números batem.

Dashboard como artefato de engenharia Dashboard versionado em JSON, publicado via CI/CD junto com o pipeline. git revert para rollback, git diff para revisão. O oposto do dashboard clicado que some quando a pessoa que construiu sai da empresa.

Números do dataset (seed 42)
Tabela	Linhas
itens_pedido	197.724
visitas	37.936
pedidos	28.729
pagamentos	27.772
oportunidades	5.979
carteira	3.637
clientes (bronze)	3.040 → 3.000 após dedup
estoque	8.400
produtos	292
vendedores	42
Total bronze	313.551
fato_vendas	191.080
Receita líquida	R$ 102.303.828,05
