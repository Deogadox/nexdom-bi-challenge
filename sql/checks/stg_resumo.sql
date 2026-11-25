/* Evidência da carga STG: contagens por tabela vs. arquivo e log da última execução. */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SELECT 'STG.ANS_Organizacoes_Ativas' AS Tabela, COUNT_BIG(*) AS Linhas, MIN(IdExecucao) AS IdExec FROM STG.ANS_Organizacoes_Ativas
UNION ALL SELECT 'STG.ANS_Organizacoes_Canceladas', COUNT_BIG(*), MIN(IdExecucao) FROM STG.ANS_Organizacoes_Canceladas
UNION ALL SELECT 'STG.ANS_IGR', COUNT_BIG(*), MIN(IdExecucao) FROM STG.ANS_IGR
UNION ALL SELECT 'STG.ANS_TR',  COUNT_BIG(*), MIN(IdExecucao) FROM STG.ANS_TR;

SELECT TOP (8) a.IdExecucao, a.TabelaDestino, a.QtdLinhas, a.Encoding, LEFT(a.Sha256, 12) AS Sha256, a.DtCarga
FROM CTL.ArquivoCarregado a ORDER BY a.IdArquivo DESC;

SELECT TOP (8) l.IdExecucao, l.Objeto, l.Status, l.LinhasLidas, l.LinhasInseridas, l.Mensagem
FROM CTL.LogEtapa l ORDER BY l.IdLog DESC;

SELECT TOP (3) IdExecucao, Origem, Status, DtInicio, DtFim, Mensagem FROM CTL.Execucao ORDER BY IdExecucao DESC;
