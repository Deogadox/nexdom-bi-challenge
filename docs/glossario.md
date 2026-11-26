# Glossário de medidas e conceitos

<!-- GERADO por src/semantic/gerar.py a partir de src/semantic/catalogo.py — não edite à mão. -->

Fonte única: [`src/semantic/catalogo.py`](../src/semantic/catalogo.py). O mesmo conteúdo alimenta a tabela
`DW.Glossario` (página *Glossário* do dashboard) e o arquivo [`powerbi/medidas.dax`](../powerbi/medidas.dax).
O código DAX de cada medida está em [`powerbi/medidas.dax`](../powerbi/medidas.dax) e na coluna `ExpressaoDAX` da tabela.

## 0 Parâmetros

| Medida | Definição | Cálculo | Unidade | Leitura | Observação |
|---|---|---|---|---|---|
| **Peso IGR Valor** | Peso do IGR no Índice Combinado, escolhido pelo usuário no parâmetro 'Peso IGR'. O peso da TR é 1 − este valor. | Valor selecionado na segmentação do parâmetro; 0,5 quando nada está selecionado. | peso (0 a 1) | Neutro | Pesos não são oficiais: servem para testar cenários. Padrão 50/50. |
| **Benef Mínimo Valor** | Volume mínimo de beneficiários médios para uma operadora entrar em rankings e medianas. | Valor selecionado no parâmetro 'Benef Mínimo'; 5.000 quando nada está selecionado. | beneficiários | Neutro | 5 mil mantém 99,5% dos beneficiários da assistência médica e remove taxas instáveis de operadoras minúsculas. |

## 1 IGR

| Medida | Definição | Cálculo | Unidade | Leitura | Observação |
|---|---|---|---|---|---|
| **Reclamações** | Quantidade de reclamações de beneficiários registradas na ANS (NIP) no período e recorte selecionados. | Soma de QtdReclamacoes do fato IGR. | reclamações | Maior = pior | Valor absoluto: cresce com o porte da operadora. Para comparar operadoras, use o IGR. |
| **Beneficiários (soma mensal)** | Soma dos beneficiários de cada mês do período. Denominador do IGR. | Soma de QtdBeneficiarios do fato IGR. | beneficiários × mês | Neutro | Não é o número de pessoas: em 12 meses, cada vínculo conta 12 vezes. Para porte, use Beneficiários Médios. |
| **Meses com IGR** | Quantidade de meses com dado de IGR no contexto (operadora, segmento, período). | Contagem distinta de SkTempo no fato IGR. | meses | Neutro | Usada nos critérios de elegibilidade e de média. |
| **Beneficiários Médios** | Média mensal de beneficiários no período. Medida de porte. | Beneficiários (soma mensal) ÷ Meses com IGR. | beneficiários | Neutro | Base do critério de elegibilidade e do eixo de porte. |
| **IGR** | Índice Geral de Reclamações: reclamações para cada 100 mil beneficiários. Indicador oficial da ANS (metodologia 2023). | Σ reclamações ÷ Σ beneficiários × 100.000 no contexto filtrado. | reclamações por 100 mil beneficiários | Maior = pior | Sempre soma/soma, nunca média de IGRs. Médico e odontológico têm escalas cerca de 50 vezes diferentes: compare dentro da mesma cobertura. |
| **IGR Mercado** | IGR de todo o mercado no mesmo período e cobertura. Referência para comparar uma operadora ou um segmento. | IGR ignorando os filtros de operadora, segmento e porte. | reclamações por 100 mil beneficiários | Maior = pior | Considera todas as operadoras. O 'mercado' do funil de outliers usa só as elegíveis. |
| **Operadoras com IGR** | Quantidade de operadoras com beneficiários e IGR no período. | Contagem distinta de operadoras no fato IGR com beneficiários > 0. | operadoras | Neutro |  |

## 2 TR

| Medida | Definição | Cálculo | Unidade | Leitura | Observação |
|---|---|---|---|---|---|
| **Demandas NIP** | Demandas de reclamação (NIP) classificadas: denominador da Taxa de Resolutividade. | Soma do denominador da TR (Inativa + NP + RVE + Núcleo). Sem filtro de natureza, usa a linha 'Geral'; com filtro, usa Assistencial e Não Assistencial. | demandas | Neutro | A natureza 'Geral' já é a soma das outras duas; a medida nunca soma as três (evita dupla contagem). Disponível só de 2015-01 a 2019-10. |
| **Demandas Resolvidas** | Demandas resolvidas por mediação, sem abertura de processo sancionador: numerador da TR. | Soma do numerador da TR (Inativa + NP + RVE), com a mesma regra de natureza de Demandas NIP. | demandas | Maior = melhor |  |
| **TR** | Taxa de Resolutividade: percentual das reclamações resolvidas na mediação da ANS. Indicador oficial. | Demandas Resolvidas ÷ Demandas NIP. | % | Maior = melhor | A ANS não publica a TR após 2019-10 (substituída pela TIR em 2025). Use no recorte 2015–2019. |

## 3 Tempo

| Medida | Definição | Cálculo | Unidade | Leitura | Observação |
|---|---|---|---|---|---|
| **Meses no Período** | Quantidade de meses com dado no período selecionado, independentemente de operadora, segmento ou porte. | Contagem distinta de SkTempo no fato IGR, removendo filtros de operadora, segmento e porte. | meses | Neutro | Referência para exigir que a operadora esteja presente em todos os meses (elegibilidade). |
| **IGR Ano Anterior** | IGR dos mesmos meses do ano anterior. | IGR com o período deslocado em 12 meses (SkTempo − 100). | reclamações por 100 mil beneficiários | Maior = pior |  |
| **Var % IGR a.a.** | Variação percentual do IGR em relação aos mesmos meses do ano anterior. | (IGR − IGR Ano Anterior) ÷ IGR Ano Anterior. | % | Positivo = piora | Só aparece se os dois períodos têm o mesmo número de meses com dado. Isso evita comparar ano parcial com ano cheio ou atravessar a lacuna 2019-05 a 2021-04. |
| **TR Ano Anterior** | TR dos mesmos meses do ano anterior. | TR com o período deslocado em 12 meses. | % | Maior = melhor | Só existe entre 2016 e 2019. |
| **Var TR a.a. (p.p.)** | Diferença da TR em relação aos mesmos meses do ano anterior, em pontos percentuais. | (TR − TR Ano Anterior) × 100. | pontos percentuais | Positivo = melhora | Em p.p., não em %: de 80% para 84% é +4,0 p.p. |

## 4 Ranking

| Medida | Definição | Cálculo | Unidade | Leitura | Observação |
|---|---|---|---|---|---|
| **Operadora Elegível** | Indica se a operadora entra em rankings e medianas no período selecionado. | 1 se a operadora tem dado em todos os meses do período e Beneficiários Médios ≥ Benef Mínimo; senão 0. | 1 = sim, 0 = não | Neutro | Operadoras não elegíveis continuam nos totais; só ficam fora de rankings e medianas. |
| **Operadoras Elegíveis** | Quantidade de operadoras elegíveis no contexto. | Contagem de operadoras com Operadora Elegível = 1. | operadoras | Neutro |  |
| **IGR Mediano (operadoras elegíveis)** | IGR da operadora típica: mediana dos IGRs das operadoras elegíveis. | Mediana do IGR por operadora entre as elegíveis. | reclamações por 100 mil beneficiários | Maior = pior | Complementa o IGR agregado, que é dominado pelas grandes. Ex.: Autogestão tem agregado 50,5 e mediana 13,1. |
| **Ranking IGR (1 = pior)** | Posição da operadora entre as elegíveis, do maior para o menor IGR. | RANKX denso do IGR, decrescente, entre as operadoras elegíveis visíveis nas segmentações. | posição | 1 = maior IGR | Use com uma única cobertura selecionada. |
| **Ranking IGR (1 = melhor)** | Posição da operadora entre as elegíveis, do menor para o maior IGR. | RANKX denso do IGR, crescente, entre as operadoras elegíveis. | posição | 1 = menor IGR | Há muitos empates em IGR = 0 no odontológico. |
| **IGR do Segmento** | IGR agregado do segmento (modalidade) a que a operadora pertence. | IGR removendo o filtro de operadora e mantendo o segmento da operadora em contexto. | reclamações por 100 mil beneficiários | Maior = pior |  |
| **IGR Relativo ao Segmento** | Quantas vezes o IGR da operadora é maior (ou menor) que o do próprio segmento. | IGR ÷ IGR do Segmento. | razão | > 1 = pior que o segmento | Responde 'quem destoa do próprio segmento'. 1,0 = igual ao segmento. |
| **Ranking no Segmento (1 = pior)** | Posição da operadora dentro do próprio segmento, do maior para o menor IGR. | RANKX denso entre as operadoras elegíveis do mesmo segmento. | posição | 1 = maior IGR do segmento |  |
| **Pior Operadora (IGR)** | Nome da operadora elegível com o maior IGR no contexto. | TOPN(1) pelo IGR decrescente entre as elegíveis. | texto | — |  |
| **Melhor Operadora (IGR)** | Nome da operadora elegível com o menor IGR no contexto. | TOPN(1) pelo IGR crescente; em caso de empate, a de maior porte. | texto | — |  |

## 5 Concentração

| Medida | Definição | Cálculo | Unidade | Leitura | Observação |
|---|---|---|---|---|---|
| **% das Reclamações** | Participação da operadora (ou do segmento) no total de reclamações selecionado. | Reclamações ÷ Reclamações de todas as operadoras visíveis. | % | Neutro |  |
| **% Acumulado das Reclamações** | Percentual acumulado das reclamações, da operadora com mais reclamações para a com menos (curva de Pareto). | Soma das reclamações das operadoras com volume ≥ ao da linha ÷ total. | % | Neutro | As 10 maiores concentram 52% das reclamações médicas nos últimos 12 meses. |

## 6 Estatística

| Medida | Definição | Cálculo | Unidade | Leitura | Observação |
|---|---|---|---|---|---|
| **Operadoras Elegíveis (R2)** | Operadoras elegíveis no recorte atual (R2) da análise estatística. | Contagem de Anl_R2Operadora com Elegivel = verdadeiro. | operadoras | Neutro | Janela fixa: nov/2025 a out/2026. |
| **Outliers Críticos (atual)** | Operadoras com IGR estatisticamente acima do esperado e discrepantes no próprio segmento (recorte atual). | Contagem com Funil = 'Acima (pior)' e OutlierConsistente = verdadeiro. | operadoras | Maior = pior | Funil de Poisson com ajuste de sobredispersão (99,8%) combinado com IQR ou z-score robusto no segmento. |
| **% Outliers Críticos** | Percentual das operadoras elegíveis classificadas como outlier crítico. | Outliers Críticos (atual) ÷ Operadoras Elegíveis (R2). | % | Maior = pior |  |
| **Excesso de Reclamações (atual)** | Reclamações acima (ou abaixo, se negativo) do que seria esperado se a operadora tivesse o IGR do mercado. | Σ reclamações observadas − Σ reclamações esperadas (taxa do mercado × beneficiários), entre as elegíveis. | reclamações | Maior = pior | Útil para priorizar: mostra onde está o volume de reclamações 'a mais'. |
| **Índice Combinado** | Indicador do projeto que combina IGR e TR numa nota de 0 a 100 (recorte 2018–19). | Peso × ScoreIGR + (1 − Peso) × ScoreTR. Os scores são percentis no grupo assistencial; o ScoreIGR é invertido (menor IGR = nota maior). | pontos (0 a 100) | Maior = melhor | Metodologia do projeto, não indicador oficial da ANS. Ordenação estável entre os pesos 30/70 e 70/30 (Spearman ≥ 0,92). |
| **Ranking Índice (1 = melhor)** | Posição da operadora pelo Índice Combinado. | RANKX denso decrescente entre as operadoras com índice. | posição | 1 = melhor | Leia dentro de um grupo assistencial (filtre médico-hospitalar ou odontológico). |
| **Operadoras Críticas (IGR alto e TR baixa)** | Operadoras com IGR acima da mediana e TR abaixo da mediana do grupo (recorte 2018–19). | Contagem com Quadrante = 'Crítico: IGR alto e TR baixa'. | operadoras | Maior = pior | 49 médico-hospitalares e 3 odontológicas. |
| **% Operadoras Críticas** | Percentual das operadoras elegíveis do recorte 2018–19 no quadrante crítico. | Operadoras Críticas ÷ elegíveis em Anl_R1Operadora. | % | Maior = pior |  |

## 7 UX

| Medida | Definição | Cálculo | Unidade | Leitura | Observação |
|---|---|---|---|---|---|
| **Aviso Cobertura** | Mensagem exibida quando mais de uma cobertura está selecionada. | Texto quando não há exatamente uma cobertura no filtro; vazio caso contrário. | texto | — | Evita misturar IGR médico e odontológico, que têm escalas cerca de 50 vezes diferentes. |
| **Texto Período** | Período do IGR efetivamente exibido, para títulos dinâmicos. | Primeiro e último mês com dado de IGR no contexto. | texto | — |  |
| **Cor IGR vs Mercado** | Cor para formatação condicional: laranja se o IGR está acima do mercado, azul se está abaixo. | Compara IGR com IGR Mercado. | código de cor | — | Use em Formatação condicional → Cor → Valor do campo. |
| **Rótulo Fonte** | Texto de rodapé com as fontes e a data da última carga do DW. | Texto fixo + maior DtCargaDW. | texto | — |  |

## Conceitos

| Termo | Definição | Onde está no modelo | Observação |
|---|---|---|---|
| **Recorte R2 — atual** | Análise do IGR nos 12 meses mais recentes da série vigente (nov/2025 a out/2026). Base dos rankings atuais, outliers e segmentos. | DimTempo.SerieIGR = VIGENTE; janela de 12 meses. | Não tem TR: a ANS não publica a TR após 2019-10. |
| **Recorte R1 — IGR × TR** | Análise conjunta de IGR e TR nos 12 meses finais da janela em que as duas bases coexistem (mai/2018 a abr/2019). | DimTempo.FlJanelaComumIGRTR = 1. | Base do Índice Combinado e do quadrante crítico. Resultado histórico, não atual. |
| **Série congelada × série vigente do IGR** | O IGR de 2015 a 2019-04 é uma série congelada; a partir de 2021-05, é a série vigente (metodologia 2023). | DimTempo.SerieIGR. | Os níveis não são comparáveis (≈ 15 contra 30–65 no médico). Não há dados de 2019-05 a 2021-04. |
| **Cobertura** | Tipo de assistência do IGR: Assistência médica ou Exclusivamente odontológica. | DimCobertura. | Sempre analisar uma cobertura por vez. |
| **Natureza da demanda (TR)** | Assistencial (cobertura de procedimentos) ou Não assistencial (contratos, mensalidades, reajustes). 'Geral' é a soma das duas. | DimNatureza; FlTotal = 1 para Geral. | Nunca somar Geral com as demais. |
| **Porte** | Classificação oficial da ANS pelo número de vínculos: Pequeno (< 20 mil), Médio (20 a 100 mil), Grande (> 100 mil). | DimPorte, no grão do fato (pode mudar mês a mês e entre coberturas). |  |
| **Segmento / Grupo assistencial** | Segmento = modalidade da operadora no cadastro da ANS (Medicina de Grupo, Cooperativa Médica, Autogestão...). Grupo assistencial = Médico-hospitalar, Odontológico ou Administradora. | DimSegmento. | As modalidades antigas 'Seguradora' e 'Administradora' estão agrupadas nos segmentos atuais (marcadas como legado). |
| **Operadora elegível** | Operadora com dado em todos os meses do período e média de pelo menos 5 mil beneficiários (no R1, também ≥ 30 demandas NIP). | Medida Operadora Elegível / coluna Elegivel das tabelas de análise. | Evita que operadoras minúsculas, com taxas instáveis, dominem rankings. |
| **Funil de Poisson** | Método que compara a taxa de cada operadora com a do mercado, com limites que se estreitam conforme o porte aumenta. | Esperado = taxa do mercado × beneficiários; limites de 99,8% ajustados por sobredispersão (Spiegelhalter, 2005). | Classifica em Acima (pior), Dentro ou Abaixo (melhor) do esperado. |
| **Outlier consistente** | Operadora fora do funil de Poisson e, ao mesmo tempo, discrepante dentro do próprio segmento. | Funil fora dos limites E (IQR do segmento OU \|z robusto\| > 3,5). | Dois critérios evitam classificar como problemática uma operadora só por diferença estrutural do segmento. |
| **Quadrante crítico** | Operadora com IGR acima e TR abaixo das medianas do seu grupo assistencial (recorte R1). | Anl_R1Operadora.Quadrante. | Uma das duas definições de 'crítica' do projeto; a outra é o outlier consistente (atual). |
| **NIP** | Notificação de Intermediação Preliminar: canal da ANS para mediar reclamações entre beneficiário e operadora. Origem dos dados de IGR e TR. | — | Classificações: Inativa, NP (não procedente), RVE (reparação voluntária e eficaz), Núcleo (encaminhada à fiscalização). |
