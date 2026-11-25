/* Evidência do DW: log da última execução, dimensões, fatos por recorte e cobertura por segmento. */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
DECLARE @Id INT = (SELECT MAX(IdExecucao) FROM CTL.Execucao);
SELECT IdExecucao, Origem, Status, DtInicio, DtFim, LEFT(Mensagem, 300) AS Mensagem FROM CTL.Execucao WHERE IdExecucao = @Id;
SELECT Etapa, Objeto, Status, LinhasLidas, LinhasInseridas, LinhasAtualizadas, DATEDIFF(MILLISECOND, DtInicio, DtFim) AS Ms, LEFT(Mensagem, 160) AS Mensagem
FROM CTL.LogEtapa WHERE IdExecucao = @Id ORDER BY IdLog;

SELECT N'DimOperadora' AS Dimensao, COUNT(*) AS Linhas FROM DW.DimOperadora
UNION ALL SELECT N'DimSegmento', COUNT(*) FROM DW.DimSegmento
UNION ALL SELECT N'DimTempo', COUNT(*) FROM DW.DimTempo
UNION ALL SELECT N'DimCobertura', COUNT(*) FROM DW.DimCobertura
UNION ALL SELECT N'DimNatureza', COUNT(*) FROM DW.DimNatureza
UNION ALL SELECT N'DimPorte', COUNT(*) FROM DW.DimPorte;

SELECT Modalidade, Segmento, GrupoAssistencial, FlModalidadeLegada FROM DW.DimSegmento ORDER BY GrupoAssistencial, Segmento;

SELECT N'FatoIGR' AS Fato, ISNULL(t.SerieIGR, N'-') AS Recorte, MIN(t.AnoMes) AS De, MAX(t.AnoMes) AS Ate, COUNT(*) AS Linhas,
       COUNT(DISTINCT f.SkOperadora) AS Operadoras, SUM(CAST(f.QtdReclamacoes AS BIGINT)) AS Reclamacoes
FROM DW.FatoIGR f JOIN DW.DimTempo t ON t.SkTempo = f.SkTempo GROUP BY t.SerieIGR
UNION ALL
SELECT N'FatoTR', n.Natureza, MIN(t.AnoMes), MAX(t.AnoMes), COUNT(*), COUNT(DISTINCT f.SkOperadora), SUM(CAST(f.Denominador AS BIGINT))
FROM DW.FatoTR f JOIN DW.DimTempo t ON t.SkTempo = f.SkTempo JOIN DW.DimNatureza n ON n.SkNatureza = f.SkNatureza GROUP BY n.Natureza;

/* Recorte 2 (IGR vigente): últimos 12 meses por segmento — sanity check (taxa = soma/soma, nunca média de taxas) */
DECLARE @Fim INT = (SELECT MAX(SkTempo) FROM DW.FatoIGR);
DECLARE @Ini INT = (SELECT YEAR(d) * 100 + MONTH(d) FROM (SELECT DATEADD(MONTH, -11, DataMes) d FROM DW.DimTempo WHERE SkTempo = @Fim) x);
SELECT s.Segmento, c.Cobertura, COUNT(DISTINCT f.SkOperadora) AS Operadoras,
       SUM(f.QtdReclamacoes) AS Reclamacoes,
       CAST(SUM(CAST(f.QtdReclamacoes AS DECIMAL(18,4))) * 100000 / NULLIF(SUM(CAST(f.QtdBeneficiarios AS DECIMAL(18,4))), 0) AS DECIMAL(10,2)) AS IGR_12m
FROM DW.FatoIGR f
JOIN DW.DimOperadora o ON o.SkOperadora = f.SkOperadora
JOIN DW.DimSegmento s ON s.SkSegmento = o.SkSegmento
JOIN DW.DimCobertura c ON c.SkCobertura = f.SkCobertura
WHERE f.SkTempo BETWEEN @Ini AND @Fim
GROUP BY s.Segmento, c.Cobertura ORDER BY c.Cobertura, IGR_12m DESC;
