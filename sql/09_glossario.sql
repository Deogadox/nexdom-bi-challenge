/* =====================================================================================
   09_glossario.sql — DW.Glossario: definição de todas as medidas e conceitos do dashboard
   GERADO por src/semantic/gerar.py a partir de src/semantic/catalogo.py — não edite à mão.
   Idempotente: recria o conteúdo a cada execução (a tabela é derivada inteiramente do catálogo).
   Execução: sqlcmd -S localhost -E -b -I -f 65001 -i sql\09_glossario.sql
   ===================================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE ANS_BI;
GO
IF OBJECT_ID(N'DW.Glossario', N'U') IS NULL
CREATE TABLE DW.Glossario (
    Ordem         SMALLINT       NOT NULL CONSTRAINT PK_DW_Glossario PRIMARY KEY,
    Tipo          NVARCHAR(10)   NOT NULL CONSTRAINT CK_DW_Glossario_Tipo CHECK (Tipo IN (N'Medida', N'Conceito')),
    Termo         NVARCHAR(80)   NOT NULL CONSTRAINT UQ_DW_Glossario_Termo UNIQUE,
    Pasta         NVARCHAR(30)   NOT NULL,     -- pasta de exibição no Power BI (ou "Conceitos")
    Definicao     NVARCHAR(600)  NOT NULL,     -- o que é, em linguagem de negócio
    Calculo       NVARCHAR(600)  NOT NULL,     -- como é calculada
    Unidade       NVARCHAR(60)   NULL,
    Sentido       NVARCHAR(40)   NULL,         -- como ler: maior = melhor / pior
    Formato       NVARCHAR(30)   NULL,         -- string de formato no Power BI
    Observacao    NVARCHAR(600)  NULL,         -- cuidados e limitações
    ExpressaoDAX  NVARCHAR(MAX)  NULL,
    DtAtualizacao DATETIME2(0)   NOT NULL CONSTRAINT DF_DW_Glossario_Dt DEFAULT SYSDATETIME()
);
GO
SET XACT_ABORT ON;
BEGIN TRAN;
TRUNCATE TABLE DW.Glossario;
INSERT DW.Glossario (Ordem, Tipo, Termo, Pasta, Definicao, Calculo, Unidade, Sentido, Formato, Observacao, ExpressaoDAX)
VALUES
    (1, N'Medida', N'Peso IGR Valor', N'0 Parâmetros', N'Peso do IGR no Índice Combinado, escolhido pelo usuário no parâmetro ''Peso IGR''. O peso da TR é 1 − este valor.', N'Valor selecionado na segmentação do parâmetro; 0,5 quando nada está selecionado.', N'peso (0 a 1)', N'Neutro', N'0.00', N'Pesos não são oficiais: servem para testar cenários. Padrão 50/50.', N'SELECTEDVALUE ( ''Peso IGR''[Peso IGR], 0.5 )'),
    (2, N'Medida', N'Benef Mínimo Valor', N'0 Parâmetros', N'Volume mínimo de beneficiários médios para uma operadora entrar em rankings e medianas.', N'Valor selecionado no parâmetro ''Benef Mínimo''; 5.000 quando nada está selecionado.', N'beneficiários', N'Neutro', N'#,##0', N'5 mil mantém 99,5% dos beneficiários da assistência médica e remove taxas instáveis de operadoras minúsculas.', N'SELECTEDVALUE ( ''Benef Mínimo''[Benef Mínimo], 5000 )'),
    (3, N'Medida', N'Reclamações', N'1 IGR', N'Quantidade de reclamações de beneficiários registradas na ANS (NIP) no período e recorte selecionados.', N'Soma de QtdReclamacoes do fato IGR.', N'reclamações', N'Maior = pior', N'#,##0', N'Valor absoluto: cresce com o porte da operadora. Para comparar operadoras, use o IGR.', N'SUM ( F_IGR[QtdReclamacoes] )'),
    (4, N'Medida', N'Beneficiários (soma mensal)', N'1 IGR', N'Soma dos beneficiários de cada mês do período. Denominador do IGR.', N'Soma de QtdBeneficiarios do fato IGR.', N'beneficiários × mês', N'Neutro', N'#,##0', N'Não é o número de pessoas: em 12 meses, cada vínculo conta 12 vezes. Para porte, use Beneficiários Médios.', N'SUM ( F_IGR[QtdBeneficiarios] )'),
    (5, N'Medida', N'Meses com IGR', N'1 IGR', N'Quantidade de meses com dado de IGR no contexto (operadora, segmento, período).', N'Contagem distinta de SkTempo no fato IGR.', N'meses', N'Neutro', N'#,##0', N'Usada nos critérios de elegibilidade e de média.', N'DISTINCTCOUNT ( F_IGR[SkTempo] )'),
    (6, N'Medida', N'Beneficiários Médios', N'1 IGR', N'Média mensal de beneficiários no período. Medida de porte.', N'Beneficiários (soma mensal) ÷ Meses com IGR.', N'beneficiários', N'Neutro', N'#,##0', N'Base do critério de elegibilidade e do eixo de porte.', N'DIVIDE ( [Beneficiários (soma mensal)], [Meses com IGR] )'),
    (7, N'Medida', N'IGR', N'1 IGR', N'Índice Geral de Reclamações: reclamações para cada 100 mil beneficiários. Indicador oficial da ANS (metodologia 2023).', N'Σ reclamações ÷ Σ beneficiários × 100.000 no contexto filtrado.', N'reclamações por 100 mil beneficiários', N'Maior = pior', N'#,##0.00', N'Sempre soma/soma, nunca média de IGRs. Médico e odontológico têm escalas cerca de 50 vezes diferentes: compare dentro da mesma cobertura.', N'DIVIDE ( [Reclamações], [Beneficiários (soma mensal)] ) * 100000'),
    (8, N'Medida', N'IGR Mercado', N'1 IGR', N'IGR de todo o mercado no mesmo período e cobertura. Referência para comparar uma operadora ou um segmento.', N'IGR ignorando os filtros de operadora, segmento e porte.', N'reclamações por 100 mil beneficiários', N'Maior = pior', N'#,##0.00', N'Considera todas as operadoras. O ''mercado'' do funil de outliers usa só as elegíveis.', N'CALCULATE ( [IGR], REMOVEFILTERS ( D_Operadora ), REMOVEFILTERS ( D_Segmento ), REMOVEFILTERS ( D_Porte ) )'),
    (9, N'Medida', N'Operadoras com IGR', N'1 IGR', N'Quantidade de operadoras com beneficiários e IGR no período.', N'Contagem distinta de operadoras no fato IGR com beneficiários > 0.', N'operadoras', N'Neutro', N'#,##0', NULL, N'CALCULATE ( DISTINCTCOUNT ( F_IGR[SkOperadora] ), F_IGR[QtdBeneficiarios] > 0 )'),
    (10, N'Medida', N'Demandas NIP', N'2 TR', N'Demandas de reclamação (NIP) classificadas: denominador da Taxa de Resolutividade.', N'Soma do denominador da TR (Inativa + NP + RVE + Núcleo). Sem filtro de natureza, usa a linha ''Geral''; com filtro, usa Assistencial e Não Assistencial.', N'demandas', N'Neutro', N'#,##0', N'A natureza ''Geral'' já é a soma das outras duas; a medida nunca soma as três (evita dupla contagem). Disponível só de 2015-01 a 2019-10.', N'VAR _ApenasTotal = NOT ISFILTERED ( D_Natureza[Natureza] )
RETURN
    IF (
        _ApenasTotal,
        CALCULATE ( SUM ( F_TR[Denominador] ), D_Natureza[FlTotal] = TRUE () ),
        CALCULATE ( SUM ( F_TR[Denominador] ), KEEPFILTERS ( D_Natureza[FlTotal] = FALSE () ) )
    )'),
    (11, N'Medida', N'Demandas Resolvidas', N'2 TR', N'Demandas resolvidas por mediação, sem abertura de processo sancionador: numerador da TR.', N'Soma do numerador da TR (Inativa + NP + RVE), com a mesma regra de natureza de Demandas NIP.', N'demandas', N'Maior = melhor', N'#,##0', NULL, N'VAR _ApenasTotal = NOT ISFILTERED ( D_Natureza[Natureza] )
RETURN
    IF (
        _ApenasTotal,
        CALCULATE ( SUM ( F_TR[Numerador] ), D_Natureza[FlTotal] = TRUE () ),
        CALCULATE ( SUM ( F_TR[Numerador] ), KEEPFILTERS ( D_Natureza[FlTotal] = FALSE () ) )
    )'),
    (12, N'Medida', N'TR', N'2 TR', N'Taxa de Resolutividade: percentual das reclamações resolvidas na mediação da ANS. Indicador oficial.', N'Demandas Resolvidas ÷ Demandas NIP.', N'%', N'Maior = melhor', N'0.0%', N'A ANS não publica a TR após 2019-10 (substituída pela TIR em 2025). Use no recorte 2015–2019.', N'DIVIDE ( [Demandas Resolvidas], [Demandas NIP] )'),
    (13, N'Medida', N'Meses no Período', N'3 Tempo', N'Quantidade de meses com dado no período selecionado, independentemente de operadora, segmento ou porte.', N'Contagem distinta de SkTempo no fato IGR, removendo filtros de operadora, segmento e porte.', N'meses', N'Neutro', N'#,##0', N'Referência para exigir que a operadora esteja presente em todos os meses (elegibilidade).', N'CALCULATE (
    DISTINCTCOUNT ( F_IGR[SkTempo] ),
    REMOVEFILTERS ( D_Operadora ), REMOVEFILTERS ( D_Segmento ), REMOVEFILTERS ( D_Porte )
)'),
    (14, N'Medida', N'IGR Ano Anterior', N'3 Tempo', N'IGR dos mesmos meses do ano anterior.', N'IGR com o período deslocado em 12 meses (SkTempo − 100).', N'reclamações por 100 mil beneficiários', N'Maior = pior', N'#,##0.00', NULL, N'VAR _MesesAnt =
    SELECTCOLUMNS ( VALUES ( D_Tempo[SkTempo] ), "SkTempo", D_Tempo[SkTempo] - 100 )
RETURN
    CALCULATE ( [IGR], REMOVEFILTERS ( D_Tempo ), TREATAS ( _MesesAnt, D_Tempo[SkTempo] ) )'),
    (15, N'Medida', N'Var % IGR a.a.', N'3 Tempo', N'Variação percentual do IGR em relação aos mesmos meses do ano anterior.', N'(IGR − IGR Ano Anterior) ÷ IGR Ano Anterior.', N'%', N'Positivo = piora', N'+0.0%;-0.0%;0.0%', N'Só aparece se os dois períodos têm o mesmo número de meses com dado. Isso evita comparar ano parcial com ano cheio ou atravessar a lacuna 2019-05 a 2021-04.', N'VAR _MesesAnt =
    SELECTCOLUMNS ( VALUES ( D_Tempo[SkTempo] ), "SkTempo", D_Tempo[SkTempo] - 100 )
VAR _QtdAtual = [Meses no Período]
VAR _QtdAnt =
    CALCULATE ( [Meses no Período], REMOVEFILTERS ( D_Tempo ), TREATAS ( _MesesAnt, D_Tempo[SkTempo] ) )
VAR _Ant = [IGR Ano Anterior]
RETURN
    IF ( _QtdAtual = _QtdAnt && NOT ISBLANK ( _Ant ), DIVIDE ( [IGR] - _Ant, _Ant ) )'),
    (16, N'Medida', N'TR Ano Anterior', N'3 Tempo', N'TR dos mesmos meses do ano anterior.', N'TR com o período deslocado em 12 meses.', N'%', N'Maior = melhor', N'0.0%', N'Só existe entre 2016 e 2019.', N'VAR _MesesAnt =
    SELECTCOLUMNS ( VALUES ( D_Tempo[SkTempo] ), "SkTempo", D_Tempo[SkTempo] - 100 )
RETURN
    CALCULATE ( [TR], REMOVEFILTERS ( D_Tempo ), TREATAS ( _MesesAnt, D_Tempo[SkTempo] ) )'),
    (17, N'Medida', N'Var TR a.a. (p.p.)', N'3 Tempo', N'Diferença da TR em relação aos mesmos meses do ano anterior, em pontos percentuais.', N'(TR − TR Ano Anterior) × 100.', N'pontos percentuais', N'Positivo = melhora', N'+0.0;-0.0;0.0', N'Em p.p., não em %: de 80% para 84% é +4,0 p.p.', N'VAR _Ant = [TR Ano Anterior]
RETURN IF ( NOT ISBLANK ( _Ant ) && NOT ISBLANK ( [TR] ), ( [TR] - _Ant ) * 100 )'),
    (18, N'Medida', N'Operadora Elegível', N'4 Ranking', N'Indica se a operadora entra em rankings e medianas no período selecionado.', N'1 se a operadora tem dado em todos os meses do período e Beneficiários Médios ≥ Benef Mínimo; senão 0.', N'1 = sim, 0 = não', N'Neutro', N'0', N'Operadoras não elegíveis continuam nos totais; só ficam fora de rankings e medianas.', N'IF (
    [Meses com IGR] = [Meses no Período] && [Beneficiários Médios] >= [Benef Mínimo Valor],
    1, 0
)'),
    (19, N'Medida', N'Operadoras Elegíveis', N'4 Ranking', N'Quantidade de operadoras elegíveis no contexto.', N'Contagem de operadoras com Operadora Elegível = 1.', N'operadoras', N'Neutro', N'#,##0', NULL, N'COUNTROWS ( FILTER ( VALUES ( D_Operadora[SkOperadora] ), [Operadora Elegível] = 1 ) )'),
    (20, N'Medida', N'IGR Mediano (operadoras elegíveis)', N'4 Ranking', N'IGR da operadora típica: mediana dos IGRs das operadoras elegíveis.', N'Mediana do IGR por operadora entre as elegíveis.', N'reclamações por 100 mil beneficiários', N'Maior = pior', N'#,##0.00', N'Complementa o IGR agregado, que é dominado pelas grandes. Ex.: Autogestão tem agregado 50,5 e mediana 13,1.', N'MEDIANX ( FILTER ( VALUES ( D_Operadora[SkOperadora] ), [Operadora Elegível] = 1 ), [IGR] )'),
    (21, N'Medida', N'Ranking IGR (1 = pior)', N'4 Ranking', N'Posição da operadora entre as elegíveis, do maior para o menor IGR.', N'RANKX denso do IGR, decrescente, entre as operadoras elegíveis visíveis nas segmentações.', N'posição', N'1 = maior IGR', N'0', N'Use com uma única cobertura selecionada.', N'VAR _Val = [IGR]
RETURN
IF (
    HASONEVALUE ( D_Operadora[NomeExibicao] ) && [Operadora Elegível] = 1,
    CALCULATE (
        RANKX (
            FILTER ( ALLSELECTED ( D_Operadora[NomeExibicao] ), [Operadora Elegível] = 1 ),
            [IGR], _Val, DESC, DENSE
        ),
        ALLSELECTED ()
    )
)'),
    (22, N'Medida', N'Ranking IGR (1 = melhor)', N'4 Ranking', N'Posição da operadora entre as elegíveis, do menor para o maior IGR.', N'RANKX denso do IGR, crescente, entre as operadoras elegíveis.', N'posição', N'1 = menor IGR', N'0', N'Há muitos empates em IGR = 0 no odontológico.', N'VAR _Val = [IGR]
RETURN
IF (
    HASONEVALUE ( D_Operadora[NomeExibicao] ) && [Operadora Elegível] = 1,
    CALCULATE (
        RANKX (
            FILTER ( ALLSELECTED ( D_Operadora[NomeExibicao] ), [Operadora Elegível] = 1 ),
            [IGR], _Val, ASC, DENSE
        ),
        ALLSELECTED ()
    )
)'),
    (23, N'Medida', N'IGR do Segmento', N'4 Ranking', N'IGR agregado do segmento (modalidade) a que a operadora pertence.', N'IGR removendo o filtro de operadora e mantendo o segmento da operadora em contexto.', N'reclamações por 100 mil beneficiários', N'Maior = pior', N'#,##0.00', NULL, N'VAR _Seg = SELECTEDVALUE ( D_Operadora[SkSegmento] )
RETURN
    CALCULATE ( [IGR], REMOVEFILTERS ( D_Operadora ), D_Operadora[SkSegmento] = _Seg )'),
    (24, N'Medida', N'IGR Relativo ao Segmento', N'4 Ranking', N'Quantas vezes o IGR da operadora é maior (ou menor) que o do próprio segmento.', N'IGR ÷ IGR do Segmento.', N'razão', N'> 1 = pior que o segmento', N'0.00x', N'Responde ''quem destoa do próprio segmento''. 1,0 = igual ao segmento.', N'DIVIDE ( [IGR], [IGR do Segmento] )'),
    (25, N'Medida', N'Ranking no Segmento (1 = pior)', N'4 Ranking', N'Posição da operadora dentro do próprio segmento, do maior para o menor IGR.', N'RANKX denso entre as operadoras elegíveis do mesmo segmento.', N'posição', N'1 = maior IGR do segmento', N'0', NULL, N'VAR _Seg = SELECTEDVALUE ( D_Operadora[SkSegmento] )
RETURN
    IF (
        HASONEVALUE ( D_Operadora[NomeExibicao] ) && [Operadora Elegível] = 1,
        RANKX (
            FILTER (
                CALCULATETABLE (
                    VALUES ( D_Operadora[NomeExibicao] ),
                    ALLSELECTED ( D_Operadora ),
                    D_Operadora[SkSegmento] = _Seg
                ),
                [Operadora Elegível] = 1
            ),
            [IGR], , DESC, DENSE
        )
    )'),
    (26, N'Medida', N'Pior Operadora (IGR)', N'4 Ranking', N'Nome da operadora elegível com o maior IGR no contexto.', N'TOPN(1) pelo IGR decrescente entre as elegíveis.', N'texto', N'—', NULL, NULL, N'CONCATENATEX (
    TOPN ( 1, FILTER ( VALUES ( D_Operadora[NomeExibicao] ), [Operadora Elegível] = 1 ), [IGR], DESC ),
    D_Operadora[NomeExibicao], ", "
)'),
    (27, N'Medida', N'Melhor Operadora (IGR)', N'4 Ranking', N'Nome da operadora elegível com o menor IGR no contexto.', N'TOPN(1) pelo IGR crescente; em caso de empate, a de maior porte.', N'texto', N'—', NULL, NULL, N'CONCATENATEX (
    TOPN ( 1, FILTER ( VALUES ( D_Operadora[NomeExibicao] ), [Operadora Elegível] = 1 ),
           [IGR], ASC, [Beneficiários Médios], DESC ),
    D_Operadora[NomeExibicao], ", "
)'),
    (28, N'Medida', N'% das Reclamações', N'5 Concentração', N'Participação da operadora (ou do segmento) no total de reclamações selecionado.', N'Reclamações ÷ Reclamações de todas as operadoras visíveis.', N'%', N'Neutro', N'0.0%', NULL, N'DIVIDE ( [Reclamações], CALCULATE ( [Reclamações], ALLSELECTED () ) )'),
    (29, N'Medida', N'% das Reclamações (Pareto)', N'5 Concentração', N'Participação da operadora no total de reclamações do mercado (todas as operadoras), para as barras do Pareto.', N'Reclamações ÷ Reclamações de todas as operadoras no período, cobertura e segmento selecionados.', N'%', N'Neutro', N'0.0%', N'Ignora o filtro Top N do visual: o total é sempre o do mercado.', N'DIVIDE ( [Reclamações], CALCULATE ( [Reclamações], REMOVEFILTERS ( D_Operadora ) ) )'),
    (30, N'Medida', N'% Acumulado das Reclamações', N'5 Concentração', N'Percentual acumulado das reclamações, da operadora com mais reclamações para a com menos (curva de Pareto).', N'Soma das reclamações das operadoras com volume ≥ ao da linha ÷ total do mercado.', N'%', N'Neutro', N'0.0%', N'Ignora o filtro Top N do visual. Assistência médica, nov/2025–out/2026: 10 operadoras = 51,1%, 20 = 64,0%, 49 = 80%.', N'VAR _Atual = [Reclamações]
VAR _Tab =
    CALCULATETABLE (
        ADDCOLUMNS ( VALUES ( D_Operadora[NomeExibicao] ), "@Rec", [Reclamações] ),
        REMOVEFILTERS ( D_Operadora )
    )
RETURN
    DIVIDE ( SUMX ( FILTER ( _Tab, [@Rec] >= _Atual ), [@Rec] ), SUMX ( _Tab, [@Rec] ) )'),
    (31, N'Medida', N'Operadoras Elegíveis (R2)', N'6 Estatística', N'Operadoras elegíveis no recorte atual (R2) da análise estatística.', N'Contagem de Anl_R2Operadora com Elegivel = verdadeiro.', N'operadoras', N'Neutro', N'#,##0', N'Janela fixa: nov/2025 a out/2026.', N'CALCULATE ( COUNTROWS ( Anl_R2Operadora ), Anl_R2Operadora[Elegivel] = TRUE () )'),
    (32, N'Medida', N'Outliers Críticos (atual)', N'6 Estatística', N'Operadoras com IGR estatisticamente acima do esperado e discrepantes no próprio segmento (recorte atual).', N'Contagem com Funil = ''Acima (pior)'' e OutlierConsistente = verdadeiro.', N'operadoras', N'Maior = pior', N'#,##0', N'Funil de Poisson com ajuste de sobredispersão (99,8%) combinado com IQR ou z-score robusto no segmento.', N'CALCULATE (
    COUNTROWS ( Anl_R2Operadora ),
    Anl_R2Operadora[OutlierConsistente] = TRUE (),
    Anl_R2Operadora[Funil] = "Acima (pior)"
)'),
    (33, N'Medida', N'% Outliers Críticos', N'6 Estatística', N'Percentual das operadoras elegíveis classificadas como outlier crítico.', N'Outliers Críticos (atual) ÷ Operadoras Elegíveis (R2).', N'%', N'Maior = pior', N'0.0%', NULL, N'DIVIDE ( [Outliers Críticos (atual)], [Operadoras Elegíveis (R2)] )'),
    (34, N'Medida', N'Excesso de Reclamações (atual)', N'6 Estatística', N'Reclamações acima (ou abaixo, se negativo) do que seria esperado se a operadora tivesse o IGR do mercado.', N'Σ reclamações observadas − Σ reclamações esperadas (taxa do mercado × beneficiários), entre as elegíveis.', N'reclamações', N'Maior = pior', N'#,##0', N'Use por operadora ou por segmento. No total geral é sempre 0 (por definição, a taxa de referência é a média das elegíveis). Útil para priorizar onde está o volume ''a mais''.', N'CALCULATE (
    SUM ( Anl_R2Operadora[Reclamacoes] ) - SUM ( Anl_R2Operadora[Esperado] ),
    Anl_R2Operadora[Elegivel] = TRUE ()
)'),
    (35, N'Medida', N'Excesso Positivo', N'6 Estatística', N'Soma do excesso de reclamações só das operadoras acima do esperado.', N'Σ (reclamações − esperado) das elegíveis com excesso positivo.', N'reclamações', N'Maior = pior', N'#,##0', N'Ignora filtros de operadora (inclusive Top N do visual). Assistência médica: 83.050.', N'CALCULATE (
    SUMX ( FILTER ( Anl_R2Operadora, Anl_R2Operadora[Elegivel] = TRUE () && Anl_R2Operadora[Reclamacoes] > Anl_R2Operadora[Esperado] ), Anl_R2Operadora[Reclamacoes] - Anl_R2Operadora[Esperado] ),
    REMOVEFILTERS ( D_Operadora )
)'),
    (36, N'Medida', N'Operadoras Acima do Esperado', N'6 Estatística', N'Quantidade de operadoras elegíveis com reclamações acima do esperado.', N'Contagem das elegíveis com reclamações > esperado.', N'operadoras', N'Maior = pior', N'#,##0', N'Assistência médica: 96.', N'CALCULATE (
    COUNTROWS ( FILTER ( Anl_R2Operadora, Anl_R2Operadora[Elegivel] = TRUE () && Anl_R2Operadora[Reclamacoes] > Anl_R2Operadora[Esperado] ) ),
    REMOVEFILTERS ( D_Operadora )
)'),
    (37, N'Medida', N'Excesso Top 15', N'6 Estatística', N'Excesso de reclamações somado das 15 operadoras com maior excesso.', N'TOPN 15 por (reclamações − esperado).', N'reclamações', N'Maior = pior', N'#,##0', N'Assistência médica: 58.890.', N'CALCULATE (
    SUMX (
        TOPN ( 15, FILTER ( Anl_R2Operadora, Anl_R2Operadora[Elegivel] = TRUE () ), Anl_R2Operadora[Reclamacoes] - Anl_R2Operadora[Esperado], DESC ),
        Anl_R2Operadora[Reclamacoes] - Anl_R2Operadora[Esperado]
    ),
    REMOVEFILTERS ( D_Operadora )
)'),
    (38, N'Medida', N'% do Excesso no Top 15', N'6 Estatística', N'Participação das 15 operadoras com maior excesso no excesso total.', N'Excesso Top 15 ÷ Excesso Positivo.', N'%', N'Neutro', N'0.0%', N'Assistência médica: 70,9%.', N'DIVIDE ( [Excesso Top 15], [Excesso Positivo] )'),
    (39, N'Medida', N'Índice Combinado', N'6 Estatística', N'Indicador do projeto que combina IGR e TR numa nota de 0 a 100 (recorte 2018–19).', N'Peso × ScoreIGR + (1 − Peso) × ScoreTR. Os scores são percentis no grupo assistencial; o ScoreIGR é invertido (menor IGR = nota maior).', N'pontos (0 a 100)', N'Maior = melhor', N'0.0', N'Metodologia do projeto, não indicador oficial da ANS. Ordenação estável entre os pesos 30/70 e 70/30 (Spearman ≥ 0,92).', N'VAR _W = [Peso IGR Valor]
RETURN
    AVERAGEX (
        FILTER ( Anl_R1Operadora, Anl_R1Operadora[Elegivel] = TRUE () ),
        _W * Anl_R1Operadora[ScoreIGR] + ( 1 - _W ) * Anl_R1Operadora[ScoreTR]
    )'),
    (40, N'Medida', N'Ranking Índice (1 = melhor)', N'6 Estatística', N'Posição da operadora pelo Índice Combinado.', N'RANKX denso decrescente entre as operadoras com índice.', N'posição', N'1 = melhor', N'0', N'Leia dentro de um grupo assistencial (filtre médico-hospitalar ou odontológico).', N'VAR _Val = [Índice Combinado]
RETURN
IF (
    HASONEVALUE ( D_Operadora[NomeExibicao] ) && NOT ISBLANK ( [Índice Combinado] ),
    CALCULATE (
        RANKX (
            FILTER ( ALLSELECTED ( D_Operadora[NomeExibicao] ), NOT ISBLANK ( [Índice Combinado] ) ),
            [Índice Combinado], _Val, DESC, DENSE
        ),
        ALLSELECTED ()
    )
)'),
    (41, N'Medida', N'Ranking Índice (1 = pior)', N'6 Estatística', N'Posição da operadora pelo Índice Combinado, do menor para o maior índice.', N'RANKX denso crescente entre as operadoras com índice.', N'posição', N'1 = pior', N'0', N'Para a tabela das 10 piores do índice. Médico-hospitalar, peso 0,5: 1º MEDICAL BRASIL (419320), índice 0,7.', N'VAR _Val = [Índice Combinado]
RETURN
IF (
    HASONEVALUE ( D_Operadora[NomeExibicao] ) && NOT ISBLANK ( [Índice Combinado] ),
    CALCULATE (
        RANKX (
            FILTER ( ALLSELECTED ( D_Operadora[NomeExibicao] ), NOT ISBLANK ( [Índice Combinado] ) ),
            [Índice Combinado], _Val, ASC, DENSE
        ),
        ALLSELECTED ()
    )
)'),
    (42, N'Medida', N'Operadoras Críticas (IGR alto e TR baixa)', N'6 Estatística', N'Operadoras com IGR acima da mediana e TR abaixo da mediana do grupo (recorte 2018–19).', N'Contagem com Quadrante = ''Crítico: IGR alto e TR baixa''.', N'operadoras', N'Maior = pior', N'#,##0', N'49 médico-hospitalares e 3 odontológicas.', N'CALCULATE (
    COUNTROWS ( Anl_R1Operadora ),
    Anl_R1Operadora[Quadrante] = "Crítico: IGR alto e TR baixa"
)'),
    (43, N'Medida', N'% Operadoras Críticas', N'6 Estatística', N'Percentual das operadoras elegíveis do recorte 2018–19 no quadrante crítico.', N'Operadoras Críticas ÷ elegíveis em Anl_R1Operadora.', N'%', N'Maior = pior', N'0.0%', NULL, N'DIVIDE (
    [Operadoras Críticas (IGR alto e TR baixa)],
    CALCULATE ( COUNTROWS ( Anl_R1Operadora ), Anl_R1Operadora[Elegivel] = TRUE () )
)'),
    (44, N'Medida', N'Aviso Cobertura', N'7 UX', N'Mensagem exibida quando mais de uma cobertura está selecionada.', N'Texto quando não há exatamente uma cobertura no filtro; vazio caso contrário.', N'texto', N'—', NULL, N'Evita misturar IGR médico e odontológico, que têm escalas cerca de 50 vezes diferentes.', N'IF (
    HASONEVALUE ( D_Cobertura[Cobertura] ),
    BLANK (),
    "Selecione uma cobertura: IGR médico e odontológico têm escalas ~50× diferentes"
)'),
    (45, N'Medida', N'Texto Período', N'7 UX', N'Período do IGR efetivamente exibido, para títulos dinâmicos.', N'Primeiro e último mês com dado de IGR no contexto.', N'texto', N'—', NULL, NULL, N'VAR _Ini = CALCULATE ( MIN ( D_Tempo[DataMes] ), F_IGR )
VAR _Fim = CALCULATE ( MAX ( D_Tempo[DataMes] ), F_IGR )
RETURN "IGR de " & FORMAT ( _Ini, "mmm/yyyy" ) & " a " & FORMAT ( _Fim, "mmm/yyyy" )'),
    (46, N'Medida', N'Cor IGR vs Mercado', N'7 UX', N'Cor para formatação condicional: laranja NEXDOM (#FF7F40) se o IGR está acima do mercado, verde Excelência (#045F51) se está abaixo.', N'Compara IGR com IGR Mercado.', N'código de cor', N'—', NULL, N'Use em Formatação condicional → Cor → Valor do campo.', N'IF ( [IGR] > [IGR Mercado], "#FF7F40", "#045F51" )'),
    (47, N'Medida', N'Título Excesso', N'7 UX', N'Título dinâmico do gráfico de reclamações acima do esperado.', N'Texto com % do Excesso no Top 15.', N'texto', N'—', NULL, N'Formatar → Geral → Título → fx → Valor do campo.', N'"15 operadoras respondem por " & FORMAT ( [% do Excesso no Top 15], "0%" ) &
" das reclamações acima do esperado"'),
    (48, N'Medida', N'Subtítulo Excesso', N'7 UX', N'Subtítulo dinâmico com o total de operadoras e de reclamações acima do esperado.', N'Texto com Operadoras Acima do Esperado, Excesso Positivo e Excesso Top 15.', N'texto', N'—', NULL, N'Formatar → Geral → Título → Subtítulo → fx.', N'FORMAT ( [Operadoras Acima do Esperado], "#,##0" ) & " operadoras ficam acima do esperado e somam " &
FORMAT ( [Excesso Positivo], "#,##0" ) & " reclamações a mais; as 15 primeiras, " &
FORMAT ( [Excesso Top 15], "#,##0" ) & "."'),
    (49, N'Medida', N'Rótulo Fonte', N'7 UX', N'Texto de rodapé com as fontes e a data da última carga do DW.', N'Texto fixo + maior DtCargaDW.', N'texto', N'—', NULL, NULL, N'"Fonte: ANS — Dados Abertos (CADOP, IGR metodologia 2023, TR). Atualização: " &
FORMAT ( MAX ( D_Operadora[DtCargaDW] ), "dd/mm/yyyy" )'),
    (50, N'Conceito', N'Recorte R2 — atual', N'Conceitos', N'Análise do IGR nos 12 meses mais recentes da série vigente (nov/2025 a out/2026). Base dos rankings atuais, outliers e segmentos.', N'DimTempo.SerieIGR = VIGENTE; janela de 12 meses.', NULL, NULL, NULL, N'Não tem TR: a ANS não publica a TR após 2019-10.', NULL),
    (51, N'Conceito', N'Recorte R1 — IGR × TR', N'Conceitos', N'Análise conjunta de IGR e TR nos 12 meses finais da janela em que as duas bases coexistem (mai/2018 a abr/2019).', N'DimTempo.FlJanelaComumIGRTR = 1.', NULL, NULL, NULL, N'Base do Índice Combinado e do quadrante crítico. Resultado histórico, não atual.', NULL),
    (52, N'Conceito', N'Série congelada × série vigente do IGR', N'Conceitos', N'O IGR de 2015 a 2019-04 é uma série congelada; a partir de 2021-05, é a série vigente (metodologia 2023).', N'DimTempo.SerieIGR.', NULL, NULL, NULL, N'Os níveis não são comparáveis (≈ 15 contra 30–65 no médico). Não há dados de 2019-05 a 2021-04.', NULL),
    (53, N'Conceito', N'Cobertura', N'Conceitos', N'Tipo de assistência do IGR: Assistência médica ou Exclusivamente odontológica.', N'DimCobertura.', NULL, NULL, NULL, N'Sempre analisar uma cobertura por vez.', NULL),
    (54, N'Conceito', N'Natureza da demanda (TR)', N'Conceitos', N'Assistencial (cobertura de procedimentos) ou Não assistencial (contratos, mensalidades, reajustes). ''Geral'' é a soma das duas.', N'DimNatureza; FlTotal = 1 para Geral.', NULL, NULL, NULL, N'Nunca somar Geral com as demais.', NULL),
    (55, N'Conceito', N'Porte', N'Conceitos', N'Classificação oficial da ANS pelo número de vínculos: Pequeno (< 20 mil), Médio (20 a 100 mil), Grande (> 100 mil).', N'DimPorte, no grão do fato (pode mudar mês a mês e entre coberturas).', NULL, NULL, NULL, NULL, NULL),
    (56, N'Conceito', N'Segmento / Grupo assistencial', N'Conceitos', N'Segmento = modalidade da operadora no cadastro da ANS (Medicina de Grupo, Cooperativa Médica, Autogestão...). Grupo assistencial = Médico-hospitalar, Odontológico ou Administradora.', N'DimSegmento.', NULL, NULL, NULL, N'As modalidades antigas ''Seguradora'' e ''Administradora'' estão agrupadas nos segmentos atuais (marcadas como legado).', NULL),
    (57, N'Conceito', N'Elegibilidade (critério)', N'Conceitos', N'Operadora com dado em todos os meses do período e média de pelo menos 5 mil beneficiários (no R1, também ≥ 30 demandas NIP).', N'Medida Operadora Elegível / coluna Elegivel das tabelas de análise.', NULL, NULL, NULL, N'Evita que operadoras minúsculas, com taxas instáveis, dominem rankings.', NULL),
    (58, N'Conceito', N'Funil de Poisson', N'Conceitos', N'Método que compara a taxa de cada operadora com a do mercado, com limites que se estreitam conforme o porte aumenta.', N'Esperado = taxa do mercado × beneficiários; limites de 99,8% ajustados por sobredispersão (Spiegelhalter, 2005).', NULL, NULL, NULL, N'Classifica em Acima (pior), Dentro ou Abaixo (melhor) do esperado.', NULL),
    (59, N'Conceito', N'Outlier consistente', N'Conceitos', N'Operadora fora do funil de Poisson e, ao mesmo tempo, discrepante dentro do próprio segmento.', N'Funil fora dos limites E (IQR do segmento OU |z robusto| > 3,5).', NULL, NULL, NULL, N'Dois critérios evitam classificar como problemática uma operadora só por diferença estrutural do segmento.', NULL),
    (60, N'Conceito', N'Quadrante crítico', N'Conceitos', N'Operadora com IGR acima e TR abaixo das medianas do seu grupo assistencial (recorte R1).', N'Anl_R1Operadora.Quadrante.', NULL, NULL, NULL, N'Uma das duas definições de ''crítica'' do projeto; a outra é o outlier consistente (atual).', NULL),
    (61, N'Conceito', N'NIP', N'Conceitos', N'Notificação de Intermediação Preliminar: canal da ANS para mediar reclamações entre beneficiário e operadora. Origem dos dados de IGR e TR.', N'—', NULL, NULL, NULL, N'Classificações: Inativa, NP (não procedente), RVE (reparação voluntária e eficaz), Núcleo (encaminhada à fiscalização).', NULL);
COMMIT;
GO
SELECT Tipo, COUNT(*) AS Termos FROM DW.Glossario GROUP BY Tipo;
PRINT N'09_glossario.sql concluído: 49 medidas e 12 conceitos.';
