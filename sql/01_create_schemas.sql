/* =====================================================================================
   01_create_schemas.sql — Banco ANS_BI, schemas e estrutura de controle/auditoria
   Alvo: SQL Server 2022 (16.x). Idempotente: pode ser reexecutado sem perda de dados.
   Execução:  sqlcmd -S localhost -E -b -i sql\01_create_schemas.sql
   ===================================================================================== */
SET NOCOUNT ON;
IF DB_ID(N'ANS_BI') IS NULL
BEGIN
    CREATE DATABASE ANS_BI;
    ALTER DATABASE ANS_BI SET RECOVERY SIMPLE;   -- banco analítico, recarregável a partir dos arquivos
END
GO
USE ANS_BI;
GO
IF SCHEMA_ID(N'STG') IS NULL EXEC (N'CREATE SCHEMA STG AUTHORIZATION dbo;');   -- Bronze: cópia fiel dos arquivos
IF SCHEMA_ID(N'ODS') IS NULL EXEC (N'CREATE SCHEMA ODS AUTHORIZATION dbo;');   -- Silver: tipado, padronizado, validado
IF SCHEMA_ID(N'DW')  IS NULL EXEC (N'CREATE SCHEMA DW  AUTHORIZATION dbo;');   -- Gold: modelo estrela
IF SCHEMA_ID(N'CTL') IS NULL EXEC (N'CREATE SCHEMA CTL AUTHORIZATION dbo;');   -- controle, logs e rejeições
GO

/* ---------- Execuções (uma por rodada do pipeline) ---------- */
IF OBJECT_ID(N'CTL.Execucao', N'U') IS NULL
CREATE TABLE CTL.Execucao (
    IdExecucao   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CTL_Execucao PRIMARY KEY,
    Origem       NVARCHAR(100)  NOT NULL,                     -- ex.: 'python:run_pipeline', 'manual:ssms'
    DtInicio     DATETIME2(0)   NOT NULL CONSTRAINT DF_CTL_Execucao_DtInicio DEFAULT SYSDATETIME(),
    DtFim        DATETIME2(0)   NULL,
    Status       VARCHAR(20)    NOT NULL CONSTRAINT DF_CTL_Execucao_Status DEFAULT 'EM_ANDAMENTO'
                 CONSTRAINT CK_CTL_Execucao_Status CHECK (Status IN ('EM_ANDAMENTO','SUCESSO','FALHA')),
    Usuario      SYSNAME        NOT NULL CONSTRAINT DF_CTL_Execucao_Usuario DEFAULT SUSER_SNAME(),
    Mensagem     NVARCHAR(4000) NULL
);
GO

/* ---------- Log por etapa ---------- */
IF OBJECT_ID(N'CTL.LogEtapa', N'U') IS NULL
BEGIN
CREATE TABLE CTL.LogEtapa (
    IdLog             BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CTL_LogEtapa PRIMARY KEY,
    IdExecucao        INT            NOT NULL CONSTRAINT FK_CTL_LogEtapa_Execucao REFERENCES CTL.Execucao(IdExecucao),
    Etapa             VARCHAR(50)    NOT NULL,                -- 'CARGA_STG','ODS','DW','VALIDACAO'
    Objeto            NVARCHAR(256)  NOT NULL,                -- tabela ou procedure
    DtInicio          DATETIME2(3)   NOT NULL,
    DtFim             DATETIME2(3)   NULL,
    LinhasLidas       INT            NULL,
    LinhasInseridas   INT            NULL,
    LinhasAtualizadas INT            NULL,
    LinhasRejeitadas  INT            NULL,
    Status            VARCHAR(20)    NOT NULL
                      CONSTRAINT CK_CTL_LogEtapa_Status CHECK (Status IN ('EM_ANDAMENTO','SUCESSO','FALHA','IGNORADO')),
    Mensagem          NVARCHAR(4000) NULL,
    ErroNumero        INT            NULL,
    ErroLinha         INT            NULL
);
CREATE INDEX IX_CTL_LogEtapa_Execucao ON CTL.LogEtapa (IdExecucao);
END
GO

/* ---------- Arquivos carregados na STG (rastreabilidade arquivo → tabela) ---------- */
IF OBJECT_ID(N'CTL.ArquivoCarregado', N'U') IS NULL
BEGIN
CREATE TABLE CTL.ArquivoCarregado (
    IdArquivo          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CTL_ArquivoCarregado PRIMARY KEY,
    IdExecucao         INT           NOT NULL CONSTRAINT FK_CTL_Arquivo_Execucao REFERENCES CTL.Execucao(IdExecucao),
    Fonte              VARCHAR(50)   NOT NULL,
    NomeArquivo        NVARCHAR(260) NOT NULL,
    CaminhoRelativo    NVARCHAR(400) NOT NULL,
    UrlOrigem          NVARCHAR(500) NULL,
    Sha256             CHAR(64)      NOT NULL,
    Bytes              BIGINT        NOT NULL,
    Encoding           VARCHAR(20)   NOT NULL,
    ServerLastModified NVARCHAR(50)  NULL,
    DtDownloadUtc      NVARCHAR(40)  NULL,
    TabelaDestino      NVARCHAR(256) NOT NULL,
    QtdLinhas          INT           NOT NULL,
    DtCarga            DATETIME2(0)  NOT NULL CONSTRAINT DF_CTL_Arquivo_DtCarga DEFAULT SYSDATETIME()
);
CREATE INDEX IX_CTL_Arquivo_Tabela_Sha ON CTL.ArquivoCarregado (TabelaDestino, Sha256);
END
GO

/* ---------- Rejeições e alertas de qualidade (nenhuma exclusão silenciosa) ----------
   ERRO   = registro não segue para o ODS (permanece na STG e aqui, com o motivo)
   ALERTA = registro segue para o ODS com flag de qualidade                                */
IF OBJECT_ID(N'CTL.Rejeicao', N'U') IS NULL
BEGIN
CREATE TABLE CTL.Rejeicao (
    IdRejeicao     BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CTL_Rejeicao PRIMARY KEY,
    IdExecucao     INT            NOT NULL CONSTRAINT FK_CTL_Rejeicao_Execucao REFERENCES CTL.Execucao(IdExecucao),
    Etapa          VARCHAR(50)    NOT NULL,
    TabelaOrigem   NVARCHAR(256)  NOT NULL,
    NrLinhaArquivo INT            NULL,
    ChaveNatural   NVARCHAR(200)  NULL,
    Regra          VARCHAR(100)   NOT NULL,
    Coluna         NVARCHAR(128)  NULL,
    ValorOriginal  NVARCHAR(4000) NULL,
    Severidade     VARCHAR(10)    NOT NULL CONSTRAINT CK_CTL_Rejeicao_Sev CHECK (Severidade IN ('ERRO','ALERTA')),
    DtRegistro     DATETIME2(0)   NOT NULL CONSTRAINT DF_CTL_Rejeicao_Dt DEFAULT SYSDATETIME()
);
CREATE INDEX IX_CTL_Rejeicao_Exec_Regra ON CTL.Rejeicao (IdExecucao, TabelaOrigem, Regra);
END
GO

/* ---------- Procedures de controle ---------- */
CREATE OR ALTER PROCEDURE CTL.usp_IniciarExecucao
    @Origem NVARCHAR(100), @IdExecucao INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT CTL.Execucao (Origem) VALUES (@Origem);
    SET @IdExecucao = SCOPE_IDENTITY();
END
GO

CREATE OR ALTER PROCEDURE CTL.usp_FinalizarExecucao
    @IdExecucao INT, @Status VARCHAR(20), @Mensagem NVARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE CTL.Execucao SET DtFim = SYSDATETIME(), Status = @Status, Mensagem = @Mensagem
    WHERE IdExecucao = @IdExecucao;
    IF @@ROWCOUNT = 0 THROW 50001, N'IdExecucao inexistente em CTL.Execucao.', 1;
END
GO

/* Abre (sem @IdLog) ou fecha (com @IdLog) o registro de uma etapa */
CREATE OR ALTER PROCEDURE CTL.usp_RegistrarEtapa
    @IdExecucao INT, @Etapa VARCHAR(50), @Objeto NVARCHAR(256), @Status VARCHAR(20),
    @IdLog BIGINT = NULL OUTPUT,
    @LinhasLidas INT = NULL, @LinhasInseridas INT = NULL, @LinhasAtualizadas INT = NULL,
    @LinhasRejeitadas INT = NULL, @Mensagem NVARCHAR(4000) = NULL,
    @ErroNumero INT = NULL, @ErroLinha INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @IdLog IS NULL
    BEGIN
        INSERT CTL.LogEtapa (IdExecucao, Etapa, Objeto, DtInicio, Status, Mensagem)
        VALUES (@IdExecucao, @Etapa, @Objeto, SYSDATETIME(), @Status, @Mensagem);
        SET @IdLog = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE CTL.LogEtapa
           SET DtFim = SYSDATETIME(), Status = @Status,
               LinhasLidas = @LinhasLidas, LinhasInseridas = @LinhasInseridas,
               LinhasAtualizadas = @LinhasAtualizadas, LinhasRejeitadas = @LinhasRejeitadas,
               Mensagem = @Mensagem, ErroNumero = @ErroNumero, ErroLinha = @ErroLinha
         WHERE IdLog = @IdLog;
END
GO

PRINT N'01_create_schemas.sql concluído: schemas STG/ODS/DW/CTL e estrutura de controle prontos.';
