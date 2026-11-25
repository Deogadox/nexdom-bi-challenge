/* =====================================================================================
   07_pipeline_orchestration.sql — dbo.usp_Pipeline_ANS: orquestra STG → ODS → DW
   1. Verifica disponibilidade da STG (tabelas com dados + arquivo registrado em CTL.ArquivoCarregado)
   2. ODS: Organizacoes → IGR → TR (IGR/TR dependem do cadastro para a flag de correspondência)
   3. Validação do ODS (reconciliação STG x ODS; falha interrompe o pipeline)
   4. DW: dimensões → fatos → validação (executado somente se as procedures do DW existirem)
   Cada etapa registra CTL.LogEtapa; falhas marcam CTL.Execucao como FALHA e relançam o erro.
   Reexecução segura: todas as etapas reconstroem seus alvos a partir da camada anterior.
   Uso:  EXEC dbo.usp_Pipeline_ANS;                         -- pipeline completo
         EXEC dbo.usp_Pipeline_ANS @AteCamada = 'ODS';      -- para após o ODS
   ===================================================================================== */
USE ANS_BI;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Pipeline_ANS
    @Origem NVARCHAR(100) = N'sql:usp_Pipeline_ANS',
    @AteCamada VARCHAR(3) = 'DW'
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @IdExecucao INT, @IdLog BIGINT, @Msg NVARCHAR(4000);
    EXEC CTL.usp_IniciarExecucao @Origem, @IdExecucao OUTPUT;
    PRINT CONCAT(N'IdExecucao = ', @IdExecucao);
    BEGIN TRY
        /* 1. Disponibilidade da STG */
        EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'VERIFICACAO', N'STG', 'EM_ANDAMENTO', @IdLog OUTPUT;
        SELECT @Msg = STRING_AGG(t.Tabela, N', ')
        FROM (VALUES (N'STG.ANS_Organizacoes_Ativas', (SELECT COUNT(*) FROM STG.ANS_Organizacoes_Ativas)),
                     (N'STG.ANS_Organizacoes_Canceladas', (SELECT COUNT(*) FROM STG.ANS_Organizacoes_Canceladas)),
                     (N'STG.ANS_IGR', (SELECT COUNT(*) FROM STG.ANS_IGR)),
                     (N'STG.ANS_TR',  (SELECT COUNT(*) FROM STG.ANS_TR))) t(Tabela, Linhas)
        WHERE t.Linhas = 0 OR NOT EXISTS (SELECT 1 FROM CTL.ArquivoCarregado a WHERE a.TabelaDestino = t.Tabela);
        IF @Msg IS NOT NULL
        BEGIN
            SET @Msg = CONCAT(N'STG sem dados ou sem registro de carga: ', @Msg, N'. Execute src.loading.load_stg.');
            THROW 50020, @Msg, 1;
        END
        EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'VERIFICACAO', N'STG', 'SUCESSO', @IdLog OUTPUT;

        /* 2–3. ODS + validação */
        EXEC dbo.usp_ODS_Organizacoes @IdExecucao;
        EXEC dbo.usp_ODS_IGR @IdExecucao;
        EXEC dbo.usp_ODS_TR @IdExecucao;
        EXEC dbo.usp_ODS_Validacao @IdExecucao;

        /* 4. DW */
        IF @AteCamada = 'DW'
        BEGIN
            IF OBJECT_ID(N'dbo.usp_DW_Carga', N'P') IS NULL
            BEGIN
                SET @IdLog = NULL;
                EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'DW', N'dbo.usp_DW_Carga', 'EM_ANDAMENTO', @IdLog OUTPUT;
                EXEC CTL.usp_RegistrarEtapa @IdExecucao, 'DW', N'dbo.usp_DW_Carga', 'IGNORADO', @IdLog OUTPUT,
                     @Mensagem = N'Procedures do DW ainda não criadas (sql/06_dw_stored_procedures.sql).';
            END
            ELSE
                /* dinâmico: o pipeline compila mesmo antes de o DW existir */
                EXEC sys.sp_executesql N'EXEC dbo.usp_DW_Carga @IdExecucao = @p', N'@p INT', @p = @IdExecucao;
        END

        EXEC CTL.usp_FinalizarExecucao @IdExecucao, 'SUCESSO';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @Msg = LEFT(CONCAT(N'Erro ', ERROR_NUMBER(), N' em ', ERROR_PROCEDURE(), N' linha ', ERROR_LINE(), N': ', ERROR_MESSAGE()), 4000);
        EXEC CTL.usp_FinalizarExecucao @IdExecucao, 'FALHA', @Msg;
        THROW;
    END CATCH
END
GO
PRINT N'07_pipeline_orchestration.sql concluído.';
