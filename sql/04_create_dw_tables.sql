/* =====================================================================================
   04_create_dw_tables.sql — Camada DW (Gold): modelo estrela para o Power BI
   Fatos separados porque as quebras diferem (IGR por cobertura; TR por natureza da demanda):
     DW.FatoIGR : operadora × cobertura × mês     (métricas aditivas: reclamações, beneficiários)
     DW.FatoTR  : operadora × natureza × mês      (métricas aditivas: numerador, denominador)
   Os fatos NÃO se relacionam entre si; a comparação IGR × TR ocorre pelas dimensões compartilhadas
   (DimOperadora, DimSegmento, DimTempo). Taxas são recalculadas no DAX/views: DIVIDE(SUM(num), SUM(den)).
   Porte fica no fato (DimPorte), pois muda ao longo do tempo e entre coberturas da mesma operadora.
   Membro desconhecido: chave -1 em cada dimensão (nenhum fato fica sem dimensão).
   Idempotente. Execução: sqlcmd -S localhost -E -b -f 65001 -i sql\04_create_dw_tables.sql
   ===================================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE ANS_BI;
GO
IF OBJECT_ID(N'DW.DimSegmento', N'U') IS NULL
CREATE TABLE DW.DimSegmento (
    SkSegmento        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DW_DimSegmento PRIMARY KEY,
    Modalidade        NVARCHAR(60)  NOT NULL CONSTRAINT UQ_DW_DimSegmento_Modalidade UNIQUE,  -- valor do CADOP
    Segmento          NVARCHAR(60)  NOT NULL,     -- agrupamento analítico (modalidades legadas → atual)
    GrupoAssistencial NVARCHAR(30)  NOT NULL,     -- Médico-hospitalar | Odontológico | Administradora | Não informado
    FlModalidadeLegada BIT          NOT NULL
);
GO
IF OBJECT_ID(N'DW.DimOperadora', N'U') IS NULL
CREATE TABLE DW.DimOperadora (
    SkOperadora             INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DW_DimOperadora PRIMARY KEY,
    RegistroANS             CHAR(6)       NOT NULL CONSTRAINT UQ_DW_DimOperadora_Registro UNIQUE,
    CNPJ                    CHAR(14)      NULL,
    RazaoSocial             NVARCHAR(200) NOT NULL,
    NomeFantasia            NVARCHAR(100) NULL,
    NomeExibicao            NVARCHAR(220) NOT NULL,     -- "Nome fantasia (registro)" ou razão social — rótulo do BI
    SkSegmento              INT           NOT NULL CONSTRAINT FK_DW_DimOperadora_Segmento REFERENCES DW.DimSegmento(SkSegmento),
    UF                      CHAR(2)       NULL,
    Cidade                  NVARCHAR(60)  NULL,
    Situacao                VARCHAR(13)   NOT NULL,     -- ATIVA | CANCELADA | NÃO INFORMADA
    DtRegistroANS           DATE          NULL,
    DtDescredenciamento     DATE          NULL,
    MotivoDescredenciamento NVARCHAR(100) NULL,
    DtCargaDW               DATETIME2(0)  NOT NULL CONSTRAINT DF_DW_DimOperadora_Dt DEFAULT SYSDATETIME()
);
GO
IF OBJECT_ID(N'DW.DimTempo', N'U') IS NULL
CREATE TABLE DW.DimTempo (
    SkTempo              INT          NOT NULL CONSTRAINT PK_DW_DimTempo PRIMARY KEY,   -- AAAAMM
    DataMes              DATE         NOT NULL CONSTRAINT UQ_DW_DimTempo_Data UNIQUE,  -- 1º dia do mês
    Ano                  SMALLINT     NOT NULL,
    Mes                  TINYINT      NOT NULL,
    NomeMes              NVARCHAR(10) NOT NULL,
    AnoMes               CHAR(7)      NOT NULL,     -- AAAA-MM
    Trimestre            TINYINT      NOT NULL,
    Semestre             TINYINT      NOT NULL,
    FlIGRDisponivel      BIT          NOT NULL,     -- existe IGR publicado na competência
    FlTRDisponivel       BIT          NOT NULL,
    FlJanelaComumIGRTR   BIT          NOT NULL,     -- recorte 1: IGR e TR coexistem
    SerieIGR             VARCHAR(9)   NULL          -- CONGELADA | VIGENTE | NULL (lacuna)
);
GO
IF OBJECT_ID(N'DW.DimCobertura', N'U') IS NULL
CREATE TABLE DW.DimCobertura (
    SkCobertura TINYINT      NOT NULL CONSTRAINT PK_DW_DimCobertura PRIMARY KEY,
    Cobertura   NVARCHAR(30) NOT NULL CONSTRAINT UQ_DW_DimCobertura UNIQUE
);
GO
IF OBJECT_ID(N'DW.DimNatureza', N'U') IS NULL
CREATE TABLE DW.DimNatureza (
    SkNatureza TINYINT      NOT NULL CONSTRAINT PK_DW_DimNatureza PRIMARY KEY,
    Natureza   NVARCHAR(16) NOT NULL CONSTRAINT UQ_DW_DimNatureza UNIQUE,
    FlTotal    BIT          NOT NULL    -- 1 = Geral (total pré-agregado: NUNCA somar com as demais)
);
GO
IF OBJECT_ID(N'DW.DimPorte', N'U') IS NULL
CREATE TABLE DW.DimPorte (
    SkPorte           TINYINT      NOT NULL CONSTRAINT PK_DW_DimPorte PRIMARY KEY,
    Porte             NVARCHAR(13) NOT NULL CONSTRAINT UQ_DW_DimPorte UNIQUE,
    Ordem             TINYINT      NOT NULL,
    FaixaBeneficiarios NVARCHAR(40) NOT NULL     -- definição oficial (dicionário IGR)
);
GO
IF OBJECT_ID(N'DW.FatoIGR', N'U') IS NULL
BEGIN
CREATE TABLE DW.FatoIGR (
    SkOperadora            INT          NOT NULL CONSTRAINT FK_DW_FatoIGR_Operadora REFERENCES DW.DimOperadora(SkOperadora),
    SkTempo                INT          NOT NULL CONSTRAINT FK_DW_FatoIGR_Tempo REFERENCES DW.DimTempo(SkTempo),
    SkCobertura            TINYINT      NOT NULL CONSTRAINT FK_DW_FatoIGR_Cobertura REFERENCES DW.DimCobertura(SkCobertura),
    SkPorte                TINYINT      NOT NULL CONSTRAINT FK_DW_FatoIGR_Porte REFERENCES DW.DimPorte(SkPorte),
    SkTempoBeneficiario    INT          NULL,      -- competência do denominador (papel; sem relacionamento no BI)
    QtdReclamacoes         INT          NOT NULL,
    QtdBeneficiarios       INT          NOT NULL,
    IGRPublicado           DECIMAL(18,2) NOT NULL, -- auditoria; análises usam o recalculado
    IGRCalculado           AS CAST(IIF(QtdBeneficiarios > 0, CAST(QtdReclamacoes AS DECIMAL(18,6)) * 100000 / QtdBeneficiarios, NULL) AS DECIMAL(18,4)) PERSISTED,
    FlIGRDivergente        BIT          NOT NULL,
    IdExecucaoDW           INT          NOT NULL,
    CONSTRAINT PK_DW_FatoIGR PRIMARY KEY CLUSTERED (SkOperadora, SkCobertura, SkTempo)
);
CREATE INDEX IX_DW_FatoIGR_Tempo ON DW.FatoIGR (SkTempo) INCLUDE (QtdReclamacoes, QtdBeneficiarios);
END
GO
IF OBJECT_ID(N'DW.FatoTR', N'U') IS NULL
BEGIN
CREATE TABLE DW.FatoTR (
    SkOperadora    INT          NOT NULL CONSTRAINT FK_DW_FatoTR_Operadora REFERENCES DW.DimOperadora(SkOperadora),
    SkTempo        INT          NOT NULL CONSTRAINT FK_DW_FatoTR_Tempo REFERENCES DW.DimTempo(SkTempo),
    SkNatureza     TINYINT      NOT NULL CONSTRAINT FK_DW_FatoTR_Natureza REFERENCES DW.DimNatureza(SkNatureza),
    Numerador      INT          NOT NULL,
    Denominador    INT          NOT NULL,
    VlTRPublicado  DECIMAL(9,2) NOT NULL,
    IdExecucaoDW   INT          NOT NULL,
    CONSTRAINT PK_DW_FatoTR PRIMARY KEY CLUSTERED (SkOperadora, SkNatureza, SkTempo)
);
CREATE INDEX IX_DW_FatoTR_Tempo ON DW.FatoTR (SkTempo) INCLUDE (Numerador, Denominador);
END
GO
PRINT N'04_create_dw_tables.sql concluído.';
