# Diagnóstico de desempenho — ODS do IGR

## Sintoma
`dbo.usp_ODS_IGR` levava de 305 a 368 s para 130 mil linhas; `usp_ODS_TR`, com lógica equivalente, 1,2 s.

## Investigação (evidências em `logs/`)
1. **Cache de planos** (`sys.dm_exec_query_stats`): vazio, pois os planos já tinham sido descartados.
2. **Query Store** (`sql/checks/perf_procedures.sql`): o tempo estava em duas instruções, e quase todo era espera:

   | Instrução | Duração | CPU |
   |---|---|---|
   | `SELECT i.* … INTO #val0` | 349 s | 1,1 s |
   | `INSERT CTL.Rejeicao` (erros) | 301 s | 0,18 s |

3. **Estatísticas de espera** (`sql/checks/perf_waits.sql`):
   - `RESOURCE_SEMAPHORE`: **684,7 s em 5 esperas** (maior: 348,9 s). Bloqueios (`LCK_*`): menos de 1 s.
   - Memória física: 7.876 MB; **memória-alvo do SQL Server: 313 MB**. `max server memory` está no padrão, sem limite.

## Causa
Espera por concessão de memória. A máquina estava sob pressão de memória, então a instância só conseguia reservar
cerca de 313 MB. Ao mesmo tempo, o otimizador superestimava a memória necessária, porque estima pelo tamanho
declarado das colunas: `i.*` levava todas as colunas brutas, a chave `CONCAT` era texto e o `CROSS APPLY` estimava
6 × 130 mil linhas antes do filtro. A consulta ficava na fila até o tempo limite de espera e então executava com a
concessão mínima.

## Correção
- **Linhas mais estreitas**: colunas explícitas nas temporárias, detecção de versões por `MIN`/`MAX` de métricas
  numéricas e filtro das linhas candidatas antes de expandir os motivos de rejeição.
- **`OPTION (MAX_GRANT_PERCENT = 10)`** nas instruções pesadas das procedures. A instrução começa na hora; se a
  memória não bastar, usa o `tempdb` (spill) em vez de esperar.
- **Fora do código**: liberar memória do Windows ou definir `min server memory` resolve na origem. Não é aplicado
  pelo projeto porque altera a configuração da instância.

## Resultado (execução 5)
Pipeline STG → ODS completo em **8 s**; `usp_ODS_IGR` caiu de 368 s para **4,3 s**, com as mesmas reconciliações
(IGR 130.155 = 130.136 + 19 duplicidades). Evidências: `docs/evidencias/`.
