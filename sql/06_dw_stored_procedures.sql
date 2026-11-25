/* =====================================================================================
   06_dw_stored_procedures.sql — Carga ODS → DW (modelo estrela)
     dbo.usp_DW_Dimensoes : MERGE das dimensões (chaves substitutas estáveis entre cargas; SCD tipo 1)
     dbo.usp_DW_Fatos     : reconstrução dos fatos (TRUNCATE + INSERT) numa transação
     dbo.usp_DW_Validacao : integridade ODS × DW (contagens, somas, membros desconhecidos)
     dbo.usp_DW_Carga     : encadeia as três (chamada por dbo.usp_Pipeline_ANS)
   Membro desconhecido: -1 (dimensões INT) / 0 (dimensões TINYINT).
   OPTION (MAX_GRANT_PERCENT = 10): ver docs/desempenho.md.
   Execução: sqlcmd -S localhost -E -b -f 65001 -i sql\06_dw_stored_procedures.sql
   ===================================================================================== */
USE ANS_BI;
GO

CREATE OR ALTER PROCEDURE dbo.usp_DW_Dimensoes @IdExecucao INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @IdLog BIGINT, @Ins INT = 0, @Upd INT = 0;
    DECLARE @m TABLE (Acao NVARCHAR(10));
    EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'DW', N'DW.Dim*', 'EM_ANDAMENTO', @IdLog OUTPUT;
    BEGIN TRY
        BEGIN TRAN;

        /* --- Dimensões de domínio fixo --- */
        MERGE DW.DimCobertura AS d
        USING (VALUES (0, N'Não informada'), (1, N'Assistência médica'), (2, N'Exclusivamente odontológica')) s(Sk, Nome)
           ON d.SkCobertura = s.Sk
        WHEN MATCHED AND d.Cobertura <> s.Nome THEN UPDATE SET Cobertura = s.Nome
        WHEN NOT MATCHED THEN INSERT (SkCobertura, Cobertura) VALUES (s.Sk, s.Nome);

        MERGE DW.DimNatureza AS d
        USING (VALUES (0, N'Não informada', 0), (1, N'Assistencial', 0), (2, N'Não Assistencial', 0), (3, N'Geral', 1)) s(Sk, Nome, FlTotal)
           ON d.SkNatureza = s.Sk
        WHEN MATCHED AND (d.Natureza <> s.Nome OR d.FlTotal <> s.FlTotal) THEN UPDATE SET Natureza = s.Nome, FlTotal = s.FlTotal
        WHEN NOT MATCHED THEN INSERT (SkNatureza, Natureza, FlTotal) VALUES (s.Sk, s.Nome, s.FlTotal);

        MERGE DW.DimPorte AS d
        USING (VALUES (0, N'Não informado', 0, N'—'),
                      (1, N'Pequeno', 1, N'abaixo de 20 mil vínculos'),
                      (2, N'Médio',   2, N'de 20 mil a 100 mil vínculos'),
                      (3, N'Grande',  3, N'acima de 100 mil vínculos')) s(Sk, Nome, Ordem, Faixa)
           ON d.SkPorte = s.Sk
        WHEN MATCHED AND (d.Porte <> s.Nome OR d.FaixaBeneficiarios <> s.Faixa) THEN UPDATE SET Porte = s.Nome, Ordem = s.Ordem, FaixaBeneficiarios = s.Faixa
        WHEN NOT MATCHED THEN INSERT (SkPorte, Porte, Ordem, FaixaBeneficiarios) VALUES (s.Sk, s.Nome, s.Ordem, s.Faixa);

        /* --- DimSegmento: modalidades do CADOP + agrupamento analítico ---
           Legadas: "Seguradora" → Seguradora Especializada em Saúde (Lei 10.185/2001 exigiu a especialização);
                    "Administradora" → Administradora de Benefícios. Mantidas com FlModalidadeLegada = 1. */
        IF NOT EXISTS (SELECT 1 FROM DW.DimSegmento WHERE SkSegmento = -1)
        BEGIN
            SET IDENTITY_INSERT DW.DimSegmento ON;
            INSERT DW.DimSegmento (SkSegmento, Modalidade, Segmento, GrupoAssistencial, FlModalidadeLegada)
            VALUES (-1, N'Não informada', N'Não informado', N'Não informado', 0);
            SET IDENTITY_INSERT DW.DimSegmento OFF;
        END
        MERGE DW.DimSegmento AS d
        USING (
            SELECT m.Modalidade,
                   Segmento = CASE m.Modalidade WHEN N'Seguradora' THEN N'Seguradora Especializada em Saúde'
                                                WHEN N'Administradora' THEN N'Administradora de Benefícios'
                                                WHEN N'Cooperativa odontológica' THEN N'Cooperativa Odontológica'
                                                ELSE m.Modalidade END,
                   GrupoAssistencial = CASE WHEN m.Modalidade IN (N'Odontologia de Grupo', N'Cooperativa odontológica') THEN N'Odontológico'
                                            WHEN m.Modalidade LIKE N'Administradora%' THEN N'Administradora'
                                            ELSE N'Médico-hospitalar' END,
                   FlModalidadeLegada = IIF(m.Modalidade IN (N'Seguradora', N'Administradora'), 1, 0)
            FROM (SELECT DISTINCT Modalidade FROM ODS.Organizacoes) m
        ) s ON d.Modalidade = s.Modalidade
        WHEN MATCHED AND (d.Segmento <> s.Segmento OR d.GrupoAssistencial <> s.GrupoAssistencial OR d.FlModalidadeLegada <> s.FlModalidadeLegada)
            THEN UPDATE SET Segmento = s.Segmento, GrupoAssistencial = s.GrupoAssistencial, FlModalidadeLegada = s.FlModalidadeLegada
        WHEN NOT MATCHED THEN INSERT (Modalidade, Segmento, GrupoAssistencial, FlModalidadeLegada)
            VALUES (s.Modalidade, s.Segmento, s.GrupoAssistencial, s.FlModalidadeLegada)
        OUTPUT $action INTO @m;

        /* --- DimOperadora (SCD tipo 1: o CADOP é um retrato atual, sem histórico de atributos) --- */
        IF NOT EXISTS (SELECT 1 FROM DW.DimOperadora WHERE SkOperadora = -1)
        BEGIN
            SET IDENTITY_INSERT DW.DimOperadora ON;
            INSERT DW.DimOperadora (SkOperadora, RegistroANS, RazaoSocial, NomeExibicao, SkSegmento, Situacao)
            VALUES (-1, '000000', N'Não informada', N'Não informada', -1, 'NÃO INFORMADA');
            SET IDENTITY_INSERT DW.DimOperadora OFF;
        END
        MERGE DW.DimOperadora AS d
        USING (
            SELECT o.RegistroANS, o.CNPJ, o.RazaoSocial, o.NomeFantasia,
                   NomeExibicao = CONCAT(COALESCE(o.NomeFantasia, o.RazaoSocial), N' (', o.RegistroANS, N')'),
                   s.SkSegmento, o.UF, o.Cidade, o.Situacao, o.DtRegistroANS, o.DtDescredenciamento, o.MotivoDescredenciamento
            FROM ODS.Organizacoes o
            JOIN DW.DimSegmento s ON s.Modalidade = o.Modalidade
            UNION ALL
            /* registros presentes nos fatos mas ausentes do cadastro (hoje: nenhum) → membro com dados mínimos */
            SELECT f.RegistroANS, NULL, MAX(f.RazaoSocialFonte), NULL,
                   CONCAT(MAX(f.RazaoSocialFonte), N' (', f.RegistroANS, N')'), -1, NULL, NULL, 'NÃO INFORMADA', NULL, NULL, NULL
            FROM (SELECT RegistroANS, RazaoSocialFonte FROM ODS.IGR WHERE FlCadastroEncontrado = 0
                  UNION ALL SELECT RegistroANS, RazaoSocialFonte FROM ODS.TR WHERE FlCadastroEncontrado = 0) f
            GROUP BY f.RegistroANS
        ) s ON d.RegistroANS = s.RegistroANS
        WHEN MATCHED AND (ISNULL(d.CNPJ, '') <> ISNULL(s.CNPJ, '') OR d.RazaoSocial <> s.RazaoSocial
                          OR ISNULL(d.NomeFantasia, N'') <> ISNULL(s.NomeFantasia, N'') OR d.SkSegmento <> s.SkSegmento
                          OR ISNULL(d.UF, '') <> ISNULL(s.UF, '') OR d.Situacao <> s.Situacao
                          OR ISNULL(d.DtDescredenciamento, '19000101') <> ISNULL(s.DtDescredenciamento, '19000101'))
            THEN UPDATE SET CNPJ = s.CNPJ, RazaoSocial = s.RazaoSocial, NomeFantasia = s.NomeFantasia, NomeExibicao = s.NomeExibicao,
                            SkSegmento = s.SkSegmento, UF = s.UF, Cidade = s.Cidade, Situacao = s.Situacao,
                            DtRegistroANS = s.DtRegistroANS, DtDescredenciamento = s.DtDescredenciamento,
                            MotivoDescredenciamento = s.MotivoDescredenciamento, DtCargaDW = SYSDATETIME()
        WHEN NOT MATCHED THEN INSERT (RegistroANS, CNPJ, RazaoSocial, NomeFantasia, NomeExibicao, SkSegmento, UF, Cidade, Situacao,
                                      DtRegistroANS, DtDescredenciamento, MotivoDescredenciamento)
            VALUES (s.RegistroANS, s.CNPJ, s.RazaoSocial, s.NomeFantasia, s.NomeExibicao, s.SkSegmento, s.UF, s.Cidade, s.Situacao,
                    s.DtRegistroANS, s.DtDescredenciamento, s.MotivoDescredenciamento)
        OUTPUT $action INTO @m
        OPTION (MAX_GRANT_PERCENT = 10);

        /* --- DimTempo: todos os meses entre a 1ª e a última competência dos fatos (lacunas incluídas e sinalizadas) --- */
        DECLARE @Ini DATE = (SELECT MIN(c) FROM (SELECT MIN(Competencia) c FROM ODS.IGR UNION ALL SELECT MIN(Competencia) FROM ODS.TR) x),
                @Fim DATE = (SELECT MAX(c) FROM (SELECT MAX(Competencia) c FROM ODS.IGR UNION ALL SELECT MAX(Competencia) FROM ODS.TR) x);
        WITH meses AS (
            SELECT TOP (DATEDIFF(MONTH, @Ini, @Fim) + 1)
                   DataMes = DATEADD(MONTH, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1, @Ini)
            FROM sys.all_objects a CROSS JOIN sys.all_objects b
        ), src AS (
            SELECT SkTempo = YEAR(m.DataMes) * 100 + MONTH(m.DataMes), m.DataMes,
                   Ano = YEAR(m.DataMes), Mes = MONTH(m.DataMes),
                   NomeMes = CHOOSE(MONTH(m.DataMes), N'Janeiro', N'Fevereiro', N'Março', N'Abril', N'Maio', N'Junho',
                                    N'Julho', N'Agosto', N'Setembro', N'Outubro', N'Novembro', N'Dezembro'),
                   AnoMes = FORMAT(m.DataMes, 'yyyy-MM'),
                   Trimestre = DATEPART(QUARTER, m.DataMes), Semestre = IIF(MONTH(m.DataMes) <= 6, 1, 2),
                   FlIGRDisponivel = IIF(i.DataMes IS NULL, 0, 1),
                   FlTRDisponivel  = IIF(t.DataMes IS NULL, 0, 1),
                   FlJanelaComumIGRTR = IIF(i.DataMes IS NOT NULL AND t.DataMes IS NOT NULL, 1, 0),
                   i.SerieIGR
            FROM meses m
            LEFT JOIN (SELECT Competencia AS DataMes, MAX(SerieIGR) AS SerieIGR FROM ODS.IGR GROUP BY Competencia) i ON i.DataMes = m.DataMes
            LEFT JOIN (SELECT DISTINCT Competencia AS DataMes FROM ODS.TR) t ON t.DataMes = m.DataMes
        )
        MERGE DW.DimTempo AS d
        USING src s ON d.SkTempo = s.SkTempo
        WHEN MATCHED AND (d.FlIGRDisponivel <> s.FlIGRDisponivel OR d.FlTRDisponivel <> s.FlTRDisponivel
                          OR d.FlJanelaComumIGRTR <> s.FlJanelaComumIGRTR OR ISNULL(d.SerieIGR, '') <> ISNULL(s.SerieIGR, ''))
            THEN UPDATE SET FlIGRDisponivel = s.FlIGRDisponivel, FlTRDisponivel = s.FlTRDisponivel,
                            FlJanelaComumIGRTR = s.FlJanelaComumIGRTR, SerieIGR = s.SerieIGR
        WHEN NOT MATCHED THEN INSERT (SkTempo, DataMes, Ano, Mes, NomeMes, AnoMes, Trimestre, Semestre,
                                      FlIGRDisponivel, FlTRDisponivel, FlJanelaComumIGRTR, SerieIGR)
            VALUES (s.SkTempo, s.DataMes, s.Ano, s.Mes, s.NomeMes, s.AnoMes, s.Trimestre, s.Semestre,
                    s.FlIGRDisponivel, s.FlTRDisponivel, s.FlJanelaComumIGRTR, s.SerieIGR)
        OUTPUT $action INTO @m;

        COMMIT;
        SELECT @Ins = SUM(IIF(Acao = N'INSERT', 1, 0)), @Upd = SUM(IIF(Acao = N'UPDATE', 1, 0)) FROM @m;
        EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'DW', N'DW.Dim*', 'SUCESSO', @IdLog OUTPUT,
             @LinhasInseridas = @Ins, @LinhasAtualizadas = @Upd,
             @Mensagem = N'MERGE: DimSegmento, DimOperadora, DimTempo (contagens); domínios fixos sincronizados.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE(), @Num INT = ERROR_NUMBER(), @Lin INT = ERROR_LINE();
        EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'DW', N'DW.Dim*', 'FALHA', @IdLog OUTPUT, @Mensagem = @Msg, @ErroNumero = @Num, @ErroLinha = @Lin;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_DW_Fatos @IdExecucao INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @IdLog BIGINT, @NIGR INT, @NTR INT;
    EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'DW', N'DW.Fato*', 'EM_ANDAMENTO', @IdLog OUTPUT;
    BEGIN TRY
        BEGIN TRAN;
        TRUNCATE TABLE DW.FatoIGR;
        INSERT DW.FatoIGR (SkOperadora, SkTempo, SkCobertura, SkPorte, SkTempoBeneficiario,
                           QtdReclamacoes, QtdBeneficiarios, IGRPublicado, FlIGRDivergente, IdExecucaoDW)
        SELECT ISNULL(o.SkOperadora, -1),
               YEAR(i.Competencia) * 100 + MONTH(i.Competencia),
               ISNULL(c.SkCobertura, 0),
               ISNULL(p.SkPorte, 0),
               YEAR(i.CompetenciaBeneficiario) * 100 + MONTH(i.CompetenciaBeneficiario),
               i.QtdReclamacoes, i.QtdBeneficiarios, i.IGRPublicado, i.FlIGRDivergente, @IdExecucao
        FROM ODS.IGR i
        LEFT JOIN DW.DimOperadora o ON o.RegistroANS = i.RegistroANS
        LEFT JOIN DW.DimCobertura c ON c.Cobertura = i.Cobertura
        LEFT JOIN DW.DimPorte p ON p.Porte = i.PorteOperadora
        OPTION (MAX_GRANT_PERCENT = 10);
        SET @NIGR = @@ROWCOUNT;

        TRUNCATE TABLE DW.FatoTR;
        INSERT DW.FatoTR (SkOperadora, SkTempo, SkNatureza, Numerador, Denominador, VlTRPublicado, IdExecucaoDW)
        SELECT ISNULL(o.SkOperadora, -1),
               YEAR(t.Competencia) * 100 + MONTH(t.Competencia),
               ISNULL(n.SkNatureza, 0),
               t.Numerador, t.Denominador, t.VlTRPublicado, @IdExecucao
        FROM ODS.TR t
        LEFT JOIN DW.DimOperadora o ON o.RegistroANS = t.RegistroANS
        LEFT JOIN DW.DimNatureza n ON n.Natureza = t.Natureza
        OPTION (MAX_GRANT_PERCENT = 10);
        SET @NTR = @@ROWCOUNT;
        COMMIT;
        DECLARE @Tot INT = @NIGR + @NTR, @Txt NVARCHAR(200) = CONCAT(N'FatoIGR=', @NIGR, N'; FatoTR=', @NTR);
        EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'DW', N'DW.Fato*', 'SUCESSO', @IdLog OUTPUT,
             @LinhasInseridas = @Tot, @Mensagem = @Txt;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE(), @Num INT = ERROR_NUMBER(), @Lin INT = ERROR_LINE();
        EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'DW', N'DW.Fato*', 'FALHA', @IdLog OUTPUT, @Mensagem = @Msg, @ErroNumero = @Num, @ErroLinha = @Lin;
        THROW;
    END CATCH
END
GO

/* V1 contagens ODS = DW | V2 somas de numeradores/denominadores ODS = DW | V3 fatos em membro desconhecido
   V4 operadoras do ODS presentes na dimensão | V5 resumo dos recortes temporais. V1, V2 e V4 interrompem o pipeline. */
CREATE OR ALTER PROCEDURE dbo.usp_DW_Validacao @IdExecucao INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @IdLog BIGINT;
    EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'VALIDACAO', N'dbo.usp_DW_Validacao', 'EM_ANDAMENTO', @IdLog OUTPUT;
    BEGIN TRY
        DROP TABLE IF EXISTS #v;
        CREATE TABLE #v (Checagem VARCHAR(40), Item NVARCHAR(60), ODS BIGINT, DW BIGINT, Bloqueante BIT);
        INSERT #v SELECT 'V1_CONTAGEM', N'FatoIGR', (SELECT COUNT_BIG(*) FROM ODS.IGR), (SELECT COUNT_BIG(*) FROM DW.FatoIGR), 1;
        INSERT #v SELECT 'V1_CONTAGEM', N'FatoTR',  (SELECT COUNT_BIG(*) FROM ODS.TR),  (SELECT COUNT_BIG(*) FROM DW.FatoTR), 1;
        INSERT #v SELECT 'V2_SOMA', N'QtdReclamacoes',   (SELECT SUM(CAST(QtdReclamacoes AS BIGINT)) FROM ODS.IGR),   (SELECT SUM(CAST(QtdReclamacoes AS BIGINT)) FROM DW.FatoIGR), 1;
        INSERT #v SELECT 'V2_SOMA', N'QtdBeneficiarios', (SELECT SUM(CAST(QtdBeneficiarios AS BIGINT)) FROM ODS.IGR), (SELECT SUM(CAST(QtdBeneficiarios AS BIGINT)) FROM DW.FatoIGR), 1;
        INSERT #v SELECT 'V2_SOMA', N'Numerador',   (SELECT SUM(CAST(Numerador AS BIGINT)) FROM ODS.TR),   (SELECT SUM(CAST(Numerador AS BIGINT)) FROM DW.FatoTR), 1;
        INSERT #v SELECT 'V2_SOMA', N'Denominador', (SELECT SUM(CAST(Denominador AS BIGINT)) FROM ODS.TR), (SELECT SUM(CAST(Denominador AS BIGINT)) FROM DW.FatoTR), 1;
        INSERT #v SELECT 'V3_MEMBRO_DESCONHECIDO', N'FatoIGR', 0,
               (SELECT COUNT_BIG(*) FROM DW.FatoIGR WHERE SkOperadora = -1 OR SkCobertura = 0 OR SkPorte = 0), 0;
        INSERT #v SELECT 'V3_MEMBRO_DESCONHECIDO', N'FatoTR', 0,
               (SELECT COUNT_BIG(*) FROM DW.FatoTR WHERE SkOperadora = -1 OR SkNatureza = 0), 0;
        INSERT #v SELECT 'V4_OPERADORAS', N'ODS.Organizacoes na DimOperadora', (SELECT COUNT_BIG(*) FROM ODS.Organizacoes),
               (SELECT COUNT_BIG(*) FROM ODS.Organizacoes o WHERE EXISTS (SELECT 1 FROM DW.DimOperadora d WHERE d.RegistroANS = o.RegistroANS)), 1;
        INSERT #v SELECT 'V5_RECORTE', N'Meses com IGR', NULL, (SELECT COUNT_BIG(*) FROM DW.DimTempo WHERE FlIGRDisponivel = 1), 0;
        INSERT #v SELECT 'V5_RECORTE', N'Meses com TR', NULL, (SELECT COUNT_BIG(*) FROM DW.DimTempo WHERE FlTRDisponivel = 1), 0;
        INSERT #v SELECT 'V5_RECORTE', N'Janela comum IGR×TR (meses)', NULL, (SELECT COUNT_BIG(*) FROM DW.DimTempo WHERE FlJanelaComumIGRTR = 1), 0;
        INSERT #v SELECT 'V5_RECORTE', N'Meses sem IGR nem TR (lacuna)', NULL, (SELECT COUNT_BIG(*) FROM DW.DimTempo WHERE FlIGRDisponivel = 0 AND FlTRDisponivel = 0), 0;

        SELECT Checagem, Item, ODS, DW,
               Resultado = CASE WHEN Checagem LIKE 'V5%' THEN 'INFO'
                                WHEN Checagem LIKE 'V3%' THEN IIF(DW = 0, 'OK', 'ALERTA')
                                WHEN ODS = DW THEN 'OK' ELSE 'FALHA' END
        FROM #v;

        IF EXISTS (SELECT 1 FROM #v WHERE Bloqueante = 1 AND ISNULL(ODS, -1) <> ISNULL(DW, -2))
            THROW 50030, N'usp_DW_Validacao: divergência ODS x DW em checagem bloqueante (V1/V2/V4).', 1;

        EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'VALIDACAO', N'dbo.usp_DW_Validacao', 'SUCESSO', @IdLog OUTPUT,
             @Mensagem = N'V1 contagens, V2 somas e V4 operadoras conferem.';
    END TRY
    BEGIN CATCH
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE(), @Num INT = ERROR_NUMBER(), @Lin INT = ERROR_LINE();
        EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'VALIDACAO', N'dbo.usp_DW_Validacao', 'FALHA', @IdLog OUTPUT, @Mensagem = @Msg, @ErroNumero = @Num, @ErroLinha = @Lin;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_DW_Carga @IdExecucao INT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.usp_DW_Dimensoes @IdExecucao;
    EXEC dbo.usp_DW_Fatos @IdExecucao;
    EXEC dbo.usp_DW_Validacao @IdExecucao;
END
GO
PRINT N'06_dw_stored_procedures.sql concluído.';
