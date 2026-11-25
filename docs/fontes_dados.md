# Fontes oficiais e estrutura dos dados

Todas as bases vêm do **Portal de Dados Abertos da ANS** (FTP PDA). As páginas do dados.gov.br indicadas no
desafio são catálogos que apontam para estes mesmos arquivos. Levantamento feito em 25/11/2026.

| Fonte | Arquivo de dados | Dicionário / nota técnica | Atualização no servidor |
|---|---|---|---|
| Operadoras ativas (CADOP) | `operadoras_de_plano_de_saude_ativas/Relatorio_cadop.csv` (~337 KB) | `dicionario_de_dados_das_operadoras_ativas.ods` | diária (25/11/2026 07:00) |
| Operadoras canceladas | `operadoras_de_plano_de_saude_canceladas/Relatorio_cadop_canceladas.csv` (~1,0 MB) | `Dicionario_de_dados_das_operadoras_canceladas.ods` | diária |
| IGR — metodologia 2023 | `IGR/IGR_versao_2023/pda-023-igr.csv` (~17 MB) | `Dicionario_IGR_versao_2023.ods`, `Ficha_Nota_Tecnica_-_IGR.pdf` | mensal (10/11/2026) |
| Taxa de Resolutividade | `taxa_de_resolutividade/pda-048-taxa_de_resolutividade.csv` (~6,5 MB) | `dicionario-pda-048-taxa_de_resolutividade.ods`, `Ficha_Nota_Tecnica_-_TR.pdf` | mensal (10/11/2026) |

Base: `https://dadosabertos.ans.gov.br/FTP/PDA/`. O diretório `IGR/` também contém `igr.csv` e `igr_anual.zip`
(2022) — **metodologia antiga**, fora do escopo, não utilizados.

> Por que incluir as canceladas? IGR e TR são séries históricas; operadoras que deixaram o mercado no período
> continuam nos fatos e precisam de modalidade (segmento) para não virarem "sem cadastro".

## Layout observado (amostra real das primeiras linhas)

Formato comum: CSV `;`, textos entre aspas, decimal com vírgula, registro ANS como texto.

**IGR** — `REGISTRO_OPERADORA; RAZAO_SOCIAL; COBERTURA; IGR; QTD_RECLAMACOES; QTD_BENEFICIARIOS; PORTE_OPERADORA; COMPETENCIA; COMPETENCIA_BENEFICIARIO; DT_ATUALIZACAO`
- Granularidade confirmada: operadora × cobertura × competência; 2015-01 → 2019-04 (congelada) e 2021-05 → 2026-10 (viva).
- Registro com 6 dígitos e zeros à esquerda (`"000515"`).
- `COMPETENCIA_BENEFICIARIO` = mês anterior à competência das reclamações (ex.: 2026-10 → 2026-09).
- Traz **porte** (`Pequeno/Médio/Grande`) e **beneficiários** → porte disponível na fonte obrigatória.
- Checagem na amostra: `IGR = QTD_RECLAMACOES / QTD_BENEFICIARIOS × 100.000` (exato a 2 casas).

**TR** — `CD_REGISTRO_ANS; NM_RAZAO_SOCIAL; TP_NATUREZA; VL_TR; NR_NUMERADOR; NR_DENOMINADOR; CD_COMPETENCIA; DT_ATUALIZACAO`
- Granularidade (hipótese): operadora × natureza (`Assistencial` / `Não Assistencial`) × competência mensal; início em 2019-10.
- Checagem na amostra: `VL_TR = NR_NUMERADOR / NR_DENOMINADOR × 100`.
- Denominadores muito pequenos (1, 2, 11 demandas) → TR mensal por operadora é ruidosa.

**CADOP** — 20 colunas: registro ANS, CNPJ, razão social, nome fantasia, **modalidade**, endereço (logradouro…CEP),
DDD/telefone/fax, e-mail, representante e cargo, região de comercialização, data de registro ANS. Snapshot (sem histórico).

## Metodologia oficial (Fichas de Nota Técnica)

**IGR** — reclamações NIP por 100.000 beneficiários.
- Numerador: média de demandas NIP no período classificadas como Em andamento, Inativa, NP, RVE ou Núcleo. Exclui "Não se Aplica".
- Denominador: média de beneficiários (vínculos, não pessoas) no período (SIB).
- **Maior = pior.** Menor granularidade: mês fechado; agregação de períodos é feita por médias.
- Inclui demandas em andamento (dado preliminar, sujeito a revisão retroativa). Administradoras de benefícios não têm IGR.

**TR** — % de demandas NIP resolvidas na mediação, sem processo sancionador.
- Numerador: Inativa + NP + RVE. Denominador: Inativa + NP + RVE + Núcleo. Exclui NA. ×100.
- **Maior = melhor.** Assistencial = tema "Cobertura"; Não assistencial = contratos, mensalidades/reajustes etc.
- Mês só é publicado com ~95% das demandas classificadas (defasagem). Sem benchmark oficial de "bom".

## Implicações para a integração

1. **Chave**: normalizar o registro ANS para texto de 6 dígitos (`zfill(6)`) nas três bases.
2. **Dimensões de quebra diferentes**: IGR quebra por *cobertura*, TR por *natureza da demanda* → não existe
   relação linha a linha entre os fatos. Integração via `dOperadora` + `dCalendario` (mês), comparando em nível
   operadora × período (agregando cobertura/natureza conforme a pergunta).
3. **Agregação correta de períodos**: nunca média de taxas. IGR da janela = média(reclamações)/média(beneficiários)×10⁵;
   TR da janela = Σnumerador/Σdenominador×100.
4. **Volume mínimo**: TR e IGR de operadoras pequenas são instáveis → critério definido na Fase 7: ≥ 5 mil
   beneficiários médios e ≥ 30 demandas NIP (ver `resultados_analises.md`).
5. **Cadastro**: modalidade vem do CADOP (ativas ∪ canceladas). Registros sem correspondência são sinalizados, não
   descartados; na prática, 100% foram encontrados.
