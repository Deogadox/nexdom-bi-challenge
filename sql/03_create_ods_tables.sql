/* =====================================================================================
   03_create_ods_tables.sql — Camada ODS (Silver): dados tipados, padronizados e validados.
   Granularidade (confirmada no profiling — docs/achados_exploracao.md):
     ODS.Organizacoes : 1 linha por registro ANS (ativas ∪ canceladas)
     ODS.IGR          : registro ANS × cobertura × competência
     ODS.TR           : registro ANS × natureza (Assistencial | Não Assistencial | Geral) × competência
   Rastreabilidade: TabelaOrigem/NrLinhaArquivo apontam para a linha exata da STG (e do arquivo).
   Idempotente: cria apenas o que não existe. Execução: sqlcmd -S localhost -E -b -i sql\03_create_ods_tables.sql
   ===================================================================================== */
USE ANS_BI;
GO
IF OBJECT_ID(N'ODS.Organizacoes', N'U') IS NULL
CREATE TABLE ODS.Organizacoes (
    RegistroANS             CHAR(6)        NOT NULL CONSTRAINT PK_ODS_Organizacoes PRIMARY KEY,
    CNPJ                    CHAR(14)       NULL,
    RazaoSocial             NVARCHAR(200)  NOT NULL,
    NomeFantasia            NVARCHAR(100)  NULL,
    Modalidade              NVARCHAR(60)   NOT NULL,     -- valor original do CADOP (mapeado para segmento no DW)
    UF                      CHAR(2)        NULL,
    Cidade                  NVARCHAR(60)   NULL,
    RegiaoComercializacao   TINYINT        NULL,
    DtRegistroANS           DATE           NULL,
    DtDescredenciamento     DATE           NULL,
    MotivoDescredenciamento NVARCHAR(100)  NULL,
    Situacao                VARCHAR(9)     NOT NULL CONSTRAINT CK_ODS_Org_Situacao CHECK (Situacao IN ('ATIVA','CANCELADA')),
    TabelaOrigem            NVARCHAR(128)  NOT NULL,
    NrLinhaArquivo          INT            NOT NULL,
    IdExecucaoODS           INT            NOT NULL,
    DtProcessamento         DATETIME2(0)   NOT NULL CONSTRAINT DF_ODS_Org_Dt DEFAULT SYSDATETIME()
);
GO
IF OBJECT_ID(N'ODS.IGR', N'U') IS NULL
CREATE TABLE ODS.IGR (
    RegistroANS             CHAR(6)        NOT NULL,
    Cobertura               NVARCHAR(30)   NOT NULL
                            CONSTRAINT CK_ODS_IGR_Cobertura CHECK (Cobertura IN (N'Assistência médica', N'Exclusivamente odontológica')),
    Competencia             DATE           NOT NULL,     -- 1º dia do mês das reclamações (numerador)
    CompetenciaBeneficiario DATE           NULL,         -- 1º dia do mês dos beneficiários (denominador)
    QtdReclamacoes          INT            NOT NULL CONSTRAINT CK_ODS_IGR_Rec CHECK (QtdReclamacoes >= 0),
    QtdBeneficiarios        INT            NOT NULL CONSTRAINT CK_ODS_IGR_Ben CHECK (QtdBeneficiarios >= 0),
    IGRPublicado            DECIMAL(18,2)  NOT NULL,     -- valor como publicado (série congelada arredondada a 1 casa)
    PorteOperadora          NVARCHAR(7)    NULL CONSTRAINT CK_ODS_IGR_Porte CHECK (PorteOperadora IN (N'Pequeno', N'Médio', N'Grande')),
    RazaoSocialFonte        NVARCHAR(200)  NULL,         -- nome como veio no arquivo (o oficial é o do CADOP)
    DtAtualizacao           DATE           NULL,
    SerieIGR                VARCHAR(9)     NOT NULL CONSTRAINT CK_ODS_IGR_Serie CHECK (SerieIGR IN ('CONGELADA','VIGENTE')),
    FlCadastroEncontrado    BIT            NOT NULL,
    FlIGRDivergente         BIT            NOT NULL,     -- |publicado − recalculado| acima da tolerância de arredondamento
    NrLinhaArquivo          INT            NOT NULL,
    IdExecucaoODS           INT            NOT NULL,
    CONSTRAINT PK_ODS_IGR PRIMARY KEY CLUSTERED (RegistroANS, Cobertura, Competencia)
);
GO
IF OBJECT_ID(N'ODS.TR', N'U') IS NULL
CREATE TABLE ODS.TR (
    RegistroANS             CHAR(6)        NOT NULL,
    Natureza                NVARCHAR(16)   NOT NULL
                            CONSTRAINT CK_ODS_TR_Natureza CHECK (Natureza IN (N'Assistencial', N'Não Assistencial', N'Geral')),
    Competencia             DATE           NOT NULL,
    Numerador               INT            NOT NULL,     -- Inativa + NP + RVE
    Denominador             INT            NOT NULL,     -- Inativa + NP + RVE + Núcleo
    VlTRPublicado           DECIMAL(9,2)   NOT NULL,
    RazaoSocialFonte        NVARCHAR(200)  NULL,
    DtAtualizacao           DATE           NULL,
    FlCadastroEncontrado    BIT            NOT NULL,
    NrLinhaArquivo          INT            NOT NULL,
    IdExecucaoODS           INT            NOT NULL,
    CONSTRAINT PK_ODS_TR PRIMARY KEY CLUSTERED (RegistroANS, Natureza, Competencia),
    CONSTRAINT CK_ODS_TR_Num CHECK (Numerador >= 0 AND Denominador > 0 AND Numerador <= Denominador)
);
GO
PRINT N'03_create_ods_tables.sql concluído.';
