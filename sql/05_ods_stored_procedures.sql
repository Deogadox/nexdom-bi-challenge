/* =====================================================================================
   05_ods_stored_procedures.sql — Tratamento STG → ODS (SQL Server 2022)
   Regras documentadas em docs/regras_de_negocio.md. Princípios:
     * Nenhuma exclusão silenciosa: toda linha da STG termina no ODS OU em CTL.Rejeicao (ERRO),
       e duplicidades descartadas ficam registradas (regra DUPLICIDADE_DESCARTADA).
     * ALERTA = linha segue para o ODS com flag; ERRO = linha não segue (permanece na STG).
     * Reprocessamento seguro: ODS é reconstruído a partir da STG vigente dentro de uma transação;
       rejeições da mesma execução/tabela são apagadas antes de serem regravadas.
     * OPTION (MAX_GRANT_PERCENT = 10) nas instruções pesadas: no ambiente de execução o SQL Server
       tinha só ~313 MB de memória-alvo e as consultas esperavam minutos por concessão de memória
       (RESOURCE_SEMAPHORE, 684 s acumulados). Com o limite, executam na hora (eventual spill no tempdb).
   Execução: sqlcmd -S localhost -E -b -f 65001 -i sql\05_ods_stored_procedures.sql
   ===================================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE ANS_BI;
GO

/* ------------------------------------------------------------------------------------
   dbo.usp_ODS_Organizacoes — CADOP ativas ∪ canceladas → ODS.Organizacoes
   ------------------------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE dbo.usp_ODS_Organizacoes @IdExecucao INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @IdLog BIGINT, @Lidas INT, @Inseridas INT, @Rejeitadas INT;
    EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'ODS', N'ODS.Organizacoes', 'EM_ANDAMENTO', @IdLog OUTPUT;
    BEGIN TRY
        BEGIN TRAN;
        DELETE CTL.Rejeicao WHERE IdExecucao = @IdExecucao AND Etapa = 'ODS'
           AND TabelaOrigem IN (N'STG.ANS_Organizacoes_Ativas', N'STG.ANS_Organizacoes_Canceladas');

        /* 1. Parsing (sem descartar nada) */
        DROP TABLE IF EXISTS #org;
        SELECT  x.TabelaOrigem, x.NrLinhaArquivo, x.Prioridade, x.Situacao,
                x.RegistroRaw,
                RegistroANS = CASE WHEN r.v <> '' AND r.v NOT LIKE '%[^0-9]%' AND LEN(r.v) <= 6
                                   THEN RIGHT('000000' + r.v, 6) END,
                CNPJ        = CASE WHEN LEN(c.v) = 14 AND c.v NOT LIKE '%[^0-9]%' THEN c.v END,
                x.CNPJRaw,
                RazaoSocial = NULLIF(TRIM(x.RazaoSocial), N''),
                NomeFantasia= NULLIF(TRIM(x.NomeFantasia), N''),
                Modalidade  = NULLIF(TRIM(x.Modalidade), N''),
                UF          = CASE WHEN TRIM(x.UF) LIKE '[A-Z][A-Z]' THEN TRIM(x.UF) END,
                Cidade      = NULLIF(TRIM(x.Cidade), N''),
                RegiaoComercializacao = TRY_CONVERT(TINYINT, NULLIF(TRIM(x.Regiao), N'')),
                x.DtRegistroRaw,
                DtRegistroANS       = TRY_CONVERT(DATE, NULLIF(TRIM(x.DtRegistroRaw), N''), 23),
                x.DtDescRaw,
                DtDescredenciamento = TRY_CONVERT(DATE, NULLIF(TRIM(x.DtDescRaw), N''), 23),
                MotivoDescredenciamento = NULLIF(TRIM(x.Motivo), N'')
        INTO #org
        FROM (
            SELECT N'STG.ANS_Organizacoes_Ativas' AS TabelaOrigem, NrLinhaArquivo, 1 AS Prioridade, 'ATIVA' AS Situacao,
                   REGISTRO_OPERADORA AS RegistroRaw, CNPJ AS CNPJRaw, RAZAO_SOCIAL AS RazaoSocial, NOME_FANTASIA AS NomeFantasia,
                   MODALIDADE AS Modalidade, UF, CIDADE AS Cidade, REGIAO_DE_COMERCIALIZACAO AS Regiao,
                   DATA_REGISTRO_ANS AS DtRegistroRaw, CAST(NULL AS NVARCHAR(50)) AS DtDescRaw, CAST(NULL AS NVARCHAR(150)) AS Motivo
            FROM STG.ANS_Organizacoes_Ativas
            UNION ALL
            SELECT N'STG.ANS_Organizacoes_Canceladas', NrLinhaArquivo, 2, 'CANCELADA',
                   REGISTRO_OPERADORA, CNPJ, RAZAO_SOCIAL, NOME_FANTASIA, MODALIDADE, UF, CIDADE, REGIAO_DE_COMERCIALIZACAO,
                   DATA_REGISTRO_ANS, DATA_DESCREDENCIAMENTO, MOTIVO_DO_DESCREDENCIAMENTO
            FROM STG.ANS_Organizacoes_Canceladas
        ) x
        CROSS APPLY (SELECT TRIM(x.RegistroRaw) AS v) r
        CROSS APPLY (SELECT TRIM(x.CNPJRaw) AS v) c OPTION (MAX_GRANT_PERCENT = 10);

        SET @Lidas = @@ROWCOUNT;

        /* 2. ERROS (linha não segue) */
        INSERT CTL.Rejeicao (IdExecucao, Etapa, TabelaOrigem, NrLinhaArquivo, ChaveNatural, Regra, Coluna, ValorOriginal, Severidade)
        SELECT @IdExecucao, 'ODS', TabelaOrigem, NrLinhaArquivo, RegistroRaw, 'REGISTRO_ANS_INVALIDO', N'REGISTRO_OPERADORA', RegistroRaw, 'ERRO'
        FROM #org WHERE RegistroANS IS NULL
        UNION ALL
        SELECT @IdExecucao, 'ODS', TabelaOrigem, NrLinhaArquivo, RegistroRaw, 'CAMPO_OBRIGATORIO_AUSENTE', N'RAZAO_SOCIAL/MODALIDADE', NULL, 'ERRO'
        FROM #org WHERE RegistroANS IS NOT NULL AND (RazaoSocial IS NULL OR Modalidade IS NULL) OPTION (MAX_GRANT_PERCENT = 10);

        /* 3. ALERTAS (linha segue com o campo nulo/flag) */
        INSERT CTL.Rejeicao (IdExecucao, Etapa, TabelaOrigem, NrLinhaArquivo, ChaveNatural, Regra, Coluna, ValorOriginal, Severidade)
        SELECT @IdExecucao, 'ODS', TabelaOrigem, NrLinhaArquivo, RegistroANS, 'CNPJ_INVALIDO', N'CNPJ', CNPJRaw, 'ALERTA'
        FROM #org WHERE RegistroANS IS NOT NULL AND CNPJ IS NULL
        UNION ALL
        SELECT @IdExecucao, 'ODS', TabelaOrigem, NrLinhaArquivo, RegistroANS, 'DATA_INVALIDA', N'DATA_REGISTRO_ANS', DtRegistroRaw, 'ALERTA'
        FROM #org WHERE RegistroANS IS NOT NULL AND DtRegistroANS IS NULL
        UNION ALL
        SELECT @IdExecucao, 'ODS', TabelaOrigem, NrLinhaArquivo, RegistroANS, 'DATA_INVALIDA', N'DATA_DESCREDENCIAMENTO', DtDescRaw, 'ALERTA'
        FROM #org WHERE Situacao = 'CANCELADA' AND RegistroANS IS NOT NULL AND DtDescredenciamento IS NULL OPTION (MAX_GRANT_PERCENT = 10);

        /* 4. Deduplicação por registro ANS: ativa prevalece sobre cancelada; depois a 1ª linha do arquivo */
        DROP TABLE IF EXISTS #ok;
        SELECT *, rn = ROW_NUMBER() OVER (PARTITION BY RegistroANS ORDER BY Prioridade, NrLinhaArquivo)
        INTO #ok
        FROM #org WHERE RegistroANS IS NOT NULL AND RazaoSocial IS NOT NULL AND Modalidade IS NOT NULL OPTION (MAX_GRANT_PERCENT = 10);

        INSERT CTL.Rejeicao (IdExecucao, Etapa, TabelaOrigem, NrLinhaArquivo, ChaveNatural, Regra, Coluna, ValorOriginal, Severidade)
        SELECT @IdExecucao, 'ODS', TabelaOrigem, NrLinhaArquivo, RegistroANS, 'DUPLICIDADE_DESCARTADA', N'REGISTRO_OPERADORA',
               CONCAT(N'Mantida versão ', (SELECT k.Situacao FROM #ok k WHERE k.RegistroANS = o.RegistroANS AND k.rn = 1)),
               'ALERTA'
        FROM #ok o WHERE rn > 1 OPTION (MAX_GRANT_PERCENT = 10);

        /* 5. Carga */
        TRUNCATE TABLE ODS.Organizacoes;
        INSERT ODS.Organizacoes (RegistroANS, CNPJ, RazaoSocial, NomeFantasia, Modalidade, UF, Cidade, RegiaoComercializacao,
                                 DtRegistroANS, DtDescredenciamento, MotivoDescredenciamento, Situacao, TabelaOrigem, NrLinhaArquivo, IdExecucaoODS)
        SELECT RegistroANS, CNPJ, RazaoSocial, NomeFantasia, Modalidade, UF, Cidade, RegiaoComercializacao,
               DtRegistroANS, DtDescredenciamento, MotivoDescredenciamento, Situacao, TabelaOrigem, NrLinhaArquivo, @IdExecucao
        FROM #ok WHERE rn = 1 OPTION (MAX_GRANT_PERCENT = 10);
        SET @Inseridas = @@ROWCOUNT;
        SET @Rejeitadas = @Lidas - @Inseridas;
        COMMIT;
        EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'ODS', N'ODS.Organizacoes', 'SUCESSO', @IdLog OUTPUT,
             @LinhasLidas = @Lidas, @LinhasInseridas = @Inseridas, @LinhasRejeitadas = @Rejeitadas;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE(), @Num INT = ERROR_NUMBER(), @Lin INT = ERROR_LINE();
        EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'ODS', N'ODS.Organizacoes', 'FALHA', @IdLog OUTPUT,
             @Mensagem = @Msg, @ErroNumero = @Num, @ErroLinha = @Lin;
        THROW;
    END CATCH
END
GO

/* ------------------------------------------------------------------------------------
   dbo.usp_ODS_IGR — STG.ANS_IGR → ODS.IGR   (depende de ODS.Organizacoes já carregado)
   ------------------------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE dbo.usp_ODS_IGR @IdExecucao INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @IdLog BIGINT, @Lidas INT, @Inseridas INT, @Rejeitadas INT;
    /* Tolerância |publicado − recalculado| por série (evidência em docs/achados_exploracao.md, A4):
       VIGENTE publicada com 2 casas → 0,0051; CONGELADA publicada com 1 casa, desvio observado ≤ 0,055 → 0,06 */
    DECLARE @TolVigente DECIMAL(9,4) = 0.0051, @TolCongelada DECIMAL(9,4) = 0.06;
    EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'ODS', N'ODS.IGR', 'EM_ANDAMENTO', @IdLog OUTPUT;
    BEGIN TRY
        BEGIN TRAN;
        DELETE CTL.Rejeicao WHERE IdExecucao = @IdExecucao AND Etapa = 'ODS' AND TabelaOrigem = N'STG.ANS_IGR';

        DROP TABLE IF EXISTS #igr;
        SELECT  s.NrLinhaArquivo,
                RegistroRaw = s.REGISTRO_OPERADORA,
                RegistroANS = CASE WHEN r.v <> '' AND r.v NOT LIKE '%[^0-9]%' AND LEN(r.v) <= 6 THEN RIGHT('000000' + r.v, 6) END,
                CoberturaRaw = s.COBERTURA,
                Cobertura   = CASE TRIM(s.COBERTURA) WHEN N'Assistência médica' THEN N'Assistência médica'
                                                    WHEN N'Exclusivamente odontológica' THEN N'Exclusivamente odontológica' END,
                CompetenciaRaw = s.COMPETENCIA,
                Competencia = TRY_CONVERT(DATE, TRIM(s.COMPETENCIA) + '-01', 23),
                CompetenciaBeneficiario = TRY_CONVERT(DATE, TRIM(s.COMPETENCIA_BENEFICIARIO) + '-01', 23),
                RecRaw = s.QTD_RECLAMACOES, QtdReclamacoes = TRY_CONVERT(INT, TRIM(s.QTD_RECLAMACOES)),
                BenRaw = s.QTD_BENEFICIARIOS, QtdBeneficiarios = TRY_CONVERT(INT, TRIM(s.QTD_BENEFICIARIOS)),
                IGRRaw = s.IGR, IGRPublicado = TRY_CONVERT(DECIMAL(18,2), REPLACE(TRIM(s.IGR), ',', '.')),
                PorteRaw = s.PORTE_OPERADORA,
                PorteOperadora = CASE TRIM(s.PORTE_OPERADORA) WHEN N'Pequeno' THEN N'Pequeno' WHEN N'Médio' THEN N'Médio'
                                                             WHEN N'Grande' THEN N'Grande' END,
                RazaoSocialFonte = NULLIF(TRIM(s.RAZAO_SOCIAL), N''),
                DtAtualizacao = TRY_CONVERT(DATE, NULLIF(TRIM(s.DT_ATUALIZACAO), N''), 23),
                FlErro = CAST(0 AS BIT)
        INTO #igr
        FROM STG.ANS_IGR s
        CROSS APPLY (SELECT TRIM(s.REGISTRO_OPERADORA) AS v) r OPTION (MAX_GRANT_PERCENT = 10);
        SET @Lidas = @@ROWCOUNT;
        UPDATE #igr SET FlErro = 1
        WHERE RegistroANS IS NULL OR Cobertura IS NULL OR Competencia IS NULL OR IGRPublicado IS NULL
           OR QtdReclamacoes IS NULL OR QtdReclamacoes < 0 OR QtdBeneficiarios IS NULL OR QtdBeneficiarios < 0;

        /* ERROS: chave ou métrica inválida → não segue */
        INSERT CTL.Rejeicao (IdExecucao, Etapa, TabelaOrigem, NrLinhaArquivo, ChaveNatural, Regra, Coluna, ValorOriginal, Severidade)
        SELECT @IdExecucao, 'ODS', N'STG.ANS_IGR', NrLinhaArquivo, RegistroRaw, v.Regra, v.Coluna, v.Valor, 'ERRO'
        FROM #igr
        CROSS APPLY (VALUES
            (IIF(RegistroANS IS NULL, 'REGISTRO_ANS_INVALIDO', NULL), N'REGISTRO_OPERADORA', RegistroRaw),
            (IIF(Cobertura IS NULL, 'DOMINIO_INVALIDO', NULL), N'COBERTURA', CoberturaRaw),
            (IIF(Competencia IS NULL, 'COMPETENCIA_INVALIDA', NULL), N'COMPETENCIA', CompetenciaRaw),
            (IIF(QtdReclamacoes IS NULL OR QtdReclamacoes < 0, 'NUMERO_INVALIDO', NULL), N'QTD_RECLAMACOES', RecRaw),
            (IIF(QtdBeneficiarios IS NULL OR QtdBeneficiarios < 0, 'NUMERO_INVALIDO', NULL), N'QTD_BENEFICIARIOS', BenRaw),
            (IIF(IGRPublicado IS NULL, 'NUMERO_INVALIDO', NULL), N'IGR', IGRRaw)
        ) v(Regra, Coluna, Valor)
        WHERE FlErro = 1 AND v.Regra IS NOT NULL OPTION (MAX_GRANT_PERCENT = 10);   -- só candidatas: estimativa pequena, sem concessão de memória inflada

        DROP TABLE IF EXISTS #val0;
        /* Colunas explícitas (não i.*): o otimizador estima memória pelo tamanho declarado das colunas */
        SELECT i.NrLinhaArquivo, i.RegistroANS, i.Cobertura, i.Competencia, i.CompetenciaBeneficiario,
               i.QtdReclamacoes, i.QtdBeneficiarios, i.IGRPublicado, i.PorteOperadora, i.RazaoSocialFonte, i.DtAtualizacao,
               i.BenRaw, i.IGRRaw, i.PorteRaw,
               SerieIGR = IIF(i.DtAtualizacao IS NULL, 'CONGELADA', 'VIGENTE'),   -- dicionário: data vazia = base congelada
               FlCadastroEncontrado = IIF(o.RegistroANS IS NULL, 0, 1),
               FlIGRDivergente = IIF(i.QtdBeneficiarios > 0
                                     AND ABS(i.IGRPublicado - CAST(i.QtdReclamacoes AS DECIMAL(18,6)) * 100000 / i.QtdBeneficiarios)
                                         > IIF(i.DtAtualizacao IS NULL, @TolCongelada, @TolVigente), 1, 0)
        INTO #val0
        FROM #igr i
        LEFT JOIN ODS.Organizacoes o ON o.RegistroANS = i.RegistroANS
        WHERE i.FlErro = 0 OPTION (MAX_GRANT_PERCENT = 10);

        /* Duplicidade: mais de uma versão das MÉTRICAS no mesmo grão (nome diferente não conta).
           Versão única ⇔ MIN = MAX de cada métrica na janela (uma passada, sem auto-join, só colunas numéricas) */
        DROP TABLE IF EXISTS #val;
        SELECT v.*, QtdVersoesGrao = IIF(
                   MIN(QtdReclamacoes)   OVER (PARTITION BY RegistroANS, Cobertura, Competencia) = MAX(QtdReclamacoes)   OVER (PARTITION BY RegistroANS, Cobertura, Competencia) AND
                   MIN(QtdBeneficiarios) OVER (PARTITION BY RegistroANS, Cobertura, Competencia) = MAX(QtdBeneficiarios) OVER (PARTITION BY RegistroANS, Cobertura, Competencia) AND
                   MIN(IGRPublicado)     OVER (PARTITION BY RegistroANS, Cobertura, Competencia) = MAX(IGRPublicado)     OVER (PARTITION BY RegistroANS, Cobertura, Competencia) AND
                   MIN(ISNULL(CompetenciaBeneficiario, '19000101')) OVER (PARTITION BY RegistroANS, Cobertura, Competencia) = MAX(ISNULL(CompetenciaBeneficiario, '19000101')) OVER (PARTITION BY RegistroANS, Cobertura, Competencia) AND
                   MIN(ISNULL(PorteOperadora, N'')) OVER (PARTITION BY RegistroANS, Cobertura, Competencia) = MAX(ISNULL(PorteOperadora, N'')) OVER (PARTITION BY RegistroANS, Cobertura, Competencia), 1, 2)
        INTO #val FROM #val0 v OPTION (MAX_GRANT_PERCENT = 10);

        /* Duplicidade conflitante (métricas diferentes) → ERRO em todas as linhas do grão: não há como escolher */
        INSERT CTL.Rejeicao (IdExecucao, Etapa, TabelaOrigem, NrLinhaArquivo, ChaveNatural, Regra, Coluna, ValorOriginal, Severidade)
        SELECT @IdExecucao, 'ODS', N'STG.ANS_IGR', NrLinhaArquivo, CONCAT(RegistroANS, '|', Cobertura, '|', Competencia),
               'DUPLICIDADE_CONFLITANTE', NULL, CONCAT(QtdReclamacoes, '|', QtdBeneficiarios, '|', IGRPublicado), 'ERRO'
        FROM #val WHERE QtdVersoesGrao > 1 OPTION (MAX_GRANT_PERCENT = 10);

        DROP TABLE IF EXISTS #fin;
        SELECT *, rn = ROW_NUMBER() OVER (PARTITION BY RegistroANS, Cobertura, Competencia ORDER BY NrLinhaArquivo)
        INTO #fin FROM #val WHERE QtdVersoesGrao = 1 OPTION (MAX_GRANT_PERCENT = 10);

        /* Duplicidade idêntica nas métricas → mantém a 1ª linha, registra as demais */
        INSERT CTL.Rejeicao (IdExecucao, Etapa, TabelaOrigem, NrLinhaArquivo, ChaveNatural, Regra, Coluna, ValorOriginal, Severidade)
        SELECT @IdExecucao, 'ODS', N'STG.ANS_IGR', NrLinhaArquivo, CONCAT(RegistroANS, '|', Cobertura, '|', Competencia),
               'DUPLICIDADE_DESCARTADA', N'RAZAO_SOCIAL', RazaoSocialFonte, 'ALERTA'
        FROM #fin WHERE rn > 1 OPTION (MAX_GRANT_PERCENT = 10);

        /* ALERTAS das linhas que seguem */
        INSERT CTL.Rejeicao (IdExecucao, Etapa, TabelaOrigem, NrLinhaArquivo, ChaveNatural, Regra, Coluna, ValorOriginal, Severidade)
        SELECT @IdExecucao, 'ODS', N'STG.ANS_IGR', NrLinhaArquivo, CONCAT(RegistroANS, '|', Cobertura, '|', Competencia), a.Regra, a.Coluna, a.Valor, 'ALERTA'
        FROM #fin
        CROSS APPLY (VALUES
            (IIF(FlCadastroEncontrado = 0, 'REGISTRO_SEM_CADASTRO', NULL), N'REGISTRO_OPERADORA', RegistroANS),
            (IIF(PorteOperadora IS NULL, 'DOMINIO_INVALIDO', NULL), N'PORTE_OPERADORA', PorteRaw),
            (IIF(QtdBeneficiarios = 0, 'DENOMINADOR_ZERO', NULL), N'QTD_BENEFICIARIOS', BenRaw),
            (IIF(FlIGRDivergente = 1, 'IGR_PUBLICADO_DIVERGENTE', NULL), N'IGR', IGRRaw)
        ) a(Regra, Coluna, Valor)
        WHERE rn = 1 AND (FlCadastroEncontrado = 0 OR PorteOperadora IS NULL OR QtdBeneficiarios = 0 OR FlIGRDivergente = 1)
          AND a.Regra IS NOT NULL OPTION (MAX_GRANT_PERCENT = 10);

        TRUNCATE TABLE ODS.IGR;
        INSERT ODS.IGR (RegistroANS, Cobertura, Competencia, CompetenciaBeneficiario, QtdReclamacoes, QtdBeneficiarios, IGRPublicado,
                        PorteOperadora, RazaoSocialFonte, DtAtualizacao, SerieIGR, FlCadastroEncontrado, FlIGRDivergente, NrLinhaArquivo, IdExecucaoODS)
        SELECT RegistroANS, Cobertura, Competencia, CompetenciaBeneficiario, QtdReclamacoes, QtdBeneficiarios, IGRPublicado,
               PorteOperadora, RazaoSocialFonte, DtAtualizacao, SerieIGR, FlCadastroEncontrado, FlIGRDivergente, NrLinhaArquivo, @IdExecucao
        FROM #fin WHERE rn = 1 OPTION (MAX_GRANT_PERCENT = 10);
        SET @Inseridas = @@ROWCOUNT;
        SET @Rejeitadas = @Lidas - @Inseridas;
        COMMIT;
        EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'ODS', N'ODS.IGR', 'SUCESSO', @IdLog OUTPUT,
             @LinhasLidas = @Lidas, @LinhasInseridas = @Inseridas, @LinhasRejeitadas = @Rejeitadas;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE(), @Num INT = ERROR_NUMBER(), @Lin INT = ERROR_LINE();
        EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'ODS', N'ODS.IGR', 'FALHA', @IdLog OUTPUT,
             @Mensagem = @Msg, @ErroNumero = @Num, @ErroLinha = @Lin;
        THROW;
    END CATCH
END
GO

/* ------------------------------------------------------------------------------------
   dbo.usp_ODS_TR — STG.ANS_TR → ODS.TR   (depende de ODS.Organizacoes já carregado)
   ------------------------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE dbo.usp_ODS_TR @IdExecucao INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @IdLog BIGINT, @Lidas INT, @Inseridas INT, @Rejeitadas INT;
    EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'ODS', N'ODS.TR', 'EM_ANDAMENTO', @IdLog OUTPUT;
    BEGIN TRY
        BEGIN TRAN;
        DELETE CTL.Rejeicao WHERE IdExecucao = @IdExecucao AND Etapa = 'ODS' AND TabelaOrigem = N'STG.ANS_TR';

        DROP TABLE IF EXISTS #tr;
        SELECT  s.NrLinhaArquivo,
                RegistroRaw = s.CD_REGISTRO_ANS,
                RegistroANS = CASE WHEN r.v <> '' AND r.v NOT LIKE '%[^0-9]%' AND LEN(r.v) <= 6 THEN RIGHT('000000' + r.v, 6) END,
                NaturezaRaw = s.TP_NATUREZA,
                Natureza = CASE TRIM(s.TP_NATUREZA) WHEN N'Assistencial' THEN N'Assistencial'
                                                    WHEN N'Não Assistencial' THEN N'Não Assistencial'
                                                    WHEN N'Geral' THEN N'Geral' END,
                CompetenciaRaw = s.CD_COMPETENCIA,
                Competencia = TRY_CONVERT(DATE, TRIM(s.CD_COMPETENCIA) + '-01', 23),
                NumRaw = s.NR_NUMERADOR,   Numerador   = TRY_CONVERT(INT, TRIM(s.NR_NUMERADOR)),
                DenRaw = s.NR_DENOMINADOR, Denominador = TRY_CONVERT(INT, TRIM(s.NR_DENOMINADOR)),
                VlRaw = s.VL_TR, VlTRPublicado = TRY_CONVERT(DECIMAL(9,2), REPLACE(TRIM(s.VL_TR), ',', '.')),
                RazaoSocialFonte = NULLIF(TRIM(s.NM_RAZAO_SOCIAL), N''),
                DtAtualizacao = TRY_CONVERT(DATE, NULLIF(TRIM(s.DT_ATUALIZACAO), N''), 23),
                FlErro = CAST(0 AS BIT)
        INTO #tr
        FROM STG.ANS_TR s
        CROSS APPLY (SELECT TRIM(s.CD_REGISTRO_ANS) AS v) r OPTION (MAX_GRANT_PERCENT = 10);
        SET @Lidas = @@ROWCOUNT;
        UPDATE #tr SET FlErro = 1
        WHERE RegistroANS IS NULL OR Natureza IS NULL OR Competencia IS NULL OR VlTRPublicado IS NULL
           OR Numerador IS NULL OR Numerador < 0 OR Denominador IS NULL OR Denominador <= 0 OR Numerador > Denominador;

        INSERT CTL.Rejeicao (IdExecucao, Etapa, TabelaOrigem, NrLinhaArquivo, ChaveNatural, Regra, Coluna, ValorOriginal, Severidade)
        SELECT @IdExecucao, 'ODS', N'STG.ANS_TR', NrLinhaArquivo, RegistroRaw, v.Regra, v.Coluna, v.Valor, 'ERRO'
        FROM #tr
        CROSS APPLY (VALUES
            (IIF(RegistroANS IS NULL, 'REGISTRO_ANS_INVALIDO', NULL), N'CD_REGISTRO_ANS', RegistroRaw),
            (IIF(Natureza IS NULL, 'DOMINIO_INVALIDO', NULL), N'TP_NATUREZA', NaturezaRaw),
            (IIF(Competencia IS NULL, 'COMPETENCIA_INVALIDA', NULL), N'CD_COMPETENCIA', CompetenciaRaw),
            (IIF(Numerador IS NULL OR Numerador < 0, 'NUMERO_INVALIDO', NULL), N'NR_NUMERADOR', NumRaw),
            (IIF(Denominador IS NULL OR Denominador <= 0, 'NUMERO_INVALIDO', NULL), N'NR_DENOMINADOR', DenRaw),
            (IIF(Numerador > Denominador, 'NUMERADOR_MAIOR_QUE_DENOMINADOR', NULL), N'NR_NUMERADOR', CONCAT(NumRaw, '/', DenRaw)),
            (IIF(VlTRPublicado IS NULL, 'NUMERO_INVALIDO', NULL), N'VL_TR', VlRaw)
        ) v(Regra, Coluna, Valor)
        WHERE FlErro = 1 AND v.Regra IS NOT NULL OPTION (MAX_GRANT_PERCENT = 10);

        DROP TABLE IF EXISTS #fin;
        SELECT t.*,
               FlCadastroEncontrado = IIF(o.RegistroANS IS NULL, 0, 1),
               Versoes = COUNT(*) OVER (PARTITION BY t.RegistroANS, t.Natureza, t.Competencia),
               rn = ROW_NUMBER() OVER (PARTITION BY t.RegistroANS, t.Natureza, t.Competencia ORDER BY t.NrLinhaArquivo)
        INTO #fin
        FROM #tr t
        LEFT JOIN ODS.Organizacoes o ON o.RegistroANS = t.RegistroANS
        WHERE t.FlErro = 0 OPTION (MAX_GRANT_PERCENT = 10);

        /* Profiling: grão único na TR. Se surgir duplicidade, não há regra segura de escolha → ERRO em todas */
        INSERT CTL.Rejeicao (IdExecucao, Etapa, TabelaOrigem, NrLinhaArquivo, ChaveNatural, Regra, Coluna, ValorOriginal, Severidade)
        SELECT @IdExecucao, 'ODS', N'STG.ANS_TR', NrLinhaArquivo, CONCAT(RegistroANS, '|', Natureza, '|', Competencia),
               'DUPLICIDADE_CONFLITANTE', NULL, CONCAT(Numerador, '/', Denominador), 'ERRO'
        FROM #fin WHERE Versoes > 1 OPTION (MAX_GRANT_PERCENT = 10);

        INSERT CTL.Rejeicao (IdExecucao, Etapa, TabelaOrigem, NrLinhaArquivo, ChaveNatural, Regra, Coluna, ValorOriginal, Severidade)
        SELECT @IdExecucao, 'ODS', N'STG.ANS_TR', NrLinhaArquivo, CONCAT(RegistroANS, '|', Natureza, '|', Competencia), a.Regra, a.Coluna, a.Valor, 'ALERTA'
        FROM #fin
        CROSS APPLY (VALUES
            (IIF(FlCadastroEncontrado = 0, 'REGISTRO_SEM_CADASTRO', NULL), N'CD_REGISTRO_ANS', RegistroANS),
            (IIF(ABS(VlTRPublicado - CAST(Numerador AS DECIMAL(18,6)) * 100 / Denominador) > 0.0051, 'TR_PUBLICADA_DIVERGENTE', NULL), N'VL_TR', VlRaw)
        ) a(Regra, Coluna, Valor)
        WHERE Versoes = 1 AND a.Regra IS NOT NULL OPTION (MAX_GRANT_PERCENT = 10);

        TRUNCATE TABLE ODS.TR;
        INSERT ODS.TR (RegistroANS, Natureza, Competencia, Numerador, Denominador, VlTRPublicado, RazaoSocialFonte, DtAtualizacao,
                       FlCadastroEncontrado, NrLinhaArquivo, IdExecucaoODS)
        SELECT RegistroANS, Natureza, Competencia, Numerador, Denominador, VlTRPublicado, RazaoSocialFonte, DtAtualizacao,
               FlCadastroEncontrado, NrLinhaArquivo, @IdExecucao
        FROM #fin WHERE Versoes = 1 OPTION (MAX_GRANT_PERCENT = 10);
        SET @Inseridas = @@ROWCOUNT;
        SET @Rejeitadas = @Lidas - @Inseridas;
        COMMIT;
        EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'ODS', N'ODS.TR', 'SUCESSO', @IdLog OUTPUT,
             @LinhasLidas = @Lidas, @LinhasInseridas = @Inseridas, @LinhasRejeitadas = @Rejeitadas;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE(), @Num INT = ERROR_NUMBER(), @Lin INT = ERROR_LINE();
        EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'ODS', N'ODS.TR', 'FALHA', @IdLog OUTPUT,
             @Mensagem = @Msg, @ErroNumero = @Num, @ErroLinha = @Lin;
        THROW;
    END CATCH
END
GO

/* ------------------------------------------------------------------------------------
   dbo.usp_ODS_Validacao — checagens de integridade do ODS (falha se reconciliação quebrar)
     R1  Reconciliação: linhas STG = linhas ODS + linhas descartadas (ERRO ou DUPLICIDADE_DESCARTADA)
     R2  TR: Geral = Assistencial + Não Assistencial (numerador e denominador) → ALERTA se violar
     R3  Cobertura de chaves IGR/TR no cadastro (informativo)
   ------------------------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE dbo.usp_ODS_Validacao @IdExecucao INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @IdLog BIGINT;
    EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'VALIDACAO', N'dbo.usp_ODS_Validacao', 'EM_ANDAMENTO', @IdLog OUTPUT;
    BEGIN TRY
        DELETE CTL.Rejeicao WHERE IdExecucao = @IdExecucao AND Etapa = 'VALIDACAO_ODS';

        DROP TABLE IF EXISTS #rec;
        WITH desc_ AS (
            SELECT TabelaOrigem, COUNT(DISTINCT NrLinhaArquivo) AS Descartadas
            FROM CTL.Rejeicao
            WHERE IdExecucao = @IdExecucao AND Etapa = 'ODS' AND (Severidade = 'ERRO' OR Regra = 'DUPLICIDADE_DESCARTADA')
            GROUP BY TabelaOrigem)
        SELECT t.Tabela, t.STG, t.ODS, ISNULL(d.Descartadas, 0) AS Descartadas,
               Ok = IIF(t.STG = t.ODS + ISNULL(d.Descartadas, 0), 1, 0)
        INTO #rec
        FROM (VALUES
              (N'Organizacoes', (SELECT COUNT(*) FROM STG.ANS_Organizacoes_Ativas) + (SELECT COUNT(*) FROM STG.ANS_Organizacoes_Canceladas),
                                (SELECT COUNT(*) FROM ODS.Organizacoes)),
              (N'IGR', (SELECT COUNT(*) FROM STG.ANS_IGR), (SELECT COUNT(*) FROM ODS.IGR)),
              (N'TR',  (SELECT COUNT(*) FROM STG.ANS_TR),  (SELECT COUNT(*) FROM ODS.TR))
        ) t(Tabela, STG, ODS)
        LEFT JOIN (SELECT N'Organizacoes' AS Tabela, SUM(Descartadas) AS Descartadas FROM desc_
                    WHERE TabelaOrigem IN (N'STG.ANS_Organizacoes_Ativas', N'STG.ANS_Organizacoes_Canceladas')
                   UNION ALL SELECT N'IGR', Descartadas FROM desc_ WHERE TabelaOrigem = N'STG.ANS_IGR'
                   UNION ALL SELECT N'TR',  Descartadas FROM desc_ WHERE TabelaOrigem = N'STG.ANS_TR') d
          ON d.Tabela = t.Tabela OPTION (MAX_GRANT_PERCENT = 10);

        /* R2 — consistência Geral = A + N */
        INSERT CTL.Rejeicao (IdExecucao, Etapa, TabelaOrigem, NrLinhaArquivo, ChaveNatural, Regra, Coluna, ValorOriginal, Severidade)
        SELECT @IdExecucao, 'VALIDACAO_ODS', N'ODS.TR', g.NrLinhaArquivo, CONCAT(g.RegistroANS, '|', g.Competencia),
               'TR_GERAL_INCONSISTENTE', N'Numerador/Denominador',
               CONCAT(N'Geral=', g.Numerador, '/', g.Denominador, N'; A+N=', ISNULL(p.Num, 0), '/', ISNULL(p.Den, 0)), 'ALERTA'
        FROM ODS.TR g
        OUTER APPLY (SELECT SUM(x.Numerador) AS Num, SUM(x.Denominador) AS Den FROM ODS.TR x
                     WHERE x.RegistroANS = g.RegistroANS AND x.Competencia = g.Competencia AND x.Natureza <> N'Geral') p
        WHERE g.Natureza = N'Geral' AND (g.Numerador <> ISNULL(p.Num, 0) OR g.Denominador <> ISNULL(p.Den, 0)) OPTION (MAX_GRANT_PERCENT = 10);

        DECLARE @Falhas INT = (SELECT COUNT(*) FROM #rec WHERE Ok = 0);

        SELECT 'R1_RECONCILIACAO' AS Checagem, Tabela, STG, ODS, Descartadas, IIF(Ok = 1, 'OK', 'FALHA') AS Resultado FROM #rec;
        SELECT 'R2_TR_GERAL_INCONSISTENTE' AS Checagem, COUNT(*) AS Ocorrencias
        FROM CTL.Rejeicao WHERE IdExecucao = @IdExecucao AND Etapa = 'VALIDACAO_ODS' AND Regra = 'TR_GERAL_INCONSISTENTE';
        SELECT 'R3_COBERTURA_CADASTRO' AS Checagem, Base, Registros, ComCadastro
        FROM (SELECT N'IGR' AS Base, COUNT(DISTINCT RegistroANS) AS Registros, COUNT(DISTINCT IIF(FlCadastroEncontrado = 1, RegistroANS, NULL)) AS ComCadastro FROM ODS.IGR
              UNION ALL
              SELECT N'TR', COUNT(DISTINCT RegistroANS), COUNT(DISTINCT IIF(FlCadastroEncontrado = 1, RegistroANS, NULL)) FROM ODS.TR) c;

        IF @Falhas > 0
            THROW 50010, N'usp_ODS_Validacao: reconciliação STG x ODS falhou (linhas sem destino).', 1;

        EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'VALIDACAO', N'dbo.usp_ODS_Validacao', 'SUCESSO', @IdLog OUTPUT,
             @Mensagem = N'R1 reconciliação OK; ver CTL.Rejeicao (Etapa VALIDACAO_ODS) para alertas.';
    END TRY
    BEGIN CATCH
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE(), @Num INT = ERROR_NUMBER(), @Lin INT = ERROR_LINE();
        EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'VALIDACAO', N'dbo.usp_ODS_Validacao', 'FALHA', @IdLog OUTPUT,
             @Mensagem = @Msg, @ErroNumero = @Num, @ErroLinha = @Lin;
        THROW;
    END CATCH
END
GO
PRINT N'05_ods_stored_procedures.sql concluído.';
