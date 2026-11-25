/* Diagnóstico AO VIVO: o que está executando no ANS_BI, o que espera e quanta memória pediu/recebeu.
   Rodar em outra janela enquanto o pipeline executa. */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SELECT r.session_id, r.status, r.command, r.wait_type, r.wait_time / 1000 AS espera_s,
       r.total_elapsed_time / 1000 AS decorrido_s, r.cpu_time AS cpu_ms,
       OBJECT_NAME(t.objectid, t.dbid) AS procedimento,
       g.requested_memory_kb / 1024 AS pedida_mb, g.granted_memory_kb / 1024 AS concedida_mb,
       g.ideal_memory_kb / 1024 AS ideal_mb, g.queue_id, g.wait_order,
       LEFT(REPLACE(REPLACE(SUBSTRING(t.text, r.statement_start_offset / 2 + 1,
            (CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text) ELSE r.statement_end_offset END
             - r.statement_start_offset) / 2 + 1), CHAR(13), ' '), CHAR(10), ' '), 200) AS instrucao
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
LEFT JOIN sys.dm_exec_query_memory_grants g ON g.session_id = r.session_id AND g.request_id = r.request_id
WHERE r.session_id <> @@SPID AND r.database_id = DB_ID(N'ANS_BI');

SELECT TOP (6) IdExecucao, Etapa, Objeto, Status, DtInicio, DtFim FROM CTL.LogEtapa ORDER BY IdLog DESC;

SELECT target_memory_kb / 1024 AS alvo_mb, total_memory_kb / 1024 AS total_mb, available_memory_kb / 1024 AS disponivel_mb,
       grantee_count, waiter_count
FROM sys.dm_exec_query_resource_semaphores WHERE resource_semaphore_id = 0 AND pool_id = 2;
