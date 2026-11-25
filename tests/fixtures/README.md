# Fixtures de teste

- `raw/igr/` e `raw/tr/`: linhas **reais** copiadas do início dos arquivos oficiais da ANS
  (`pda-023-igr.csv` e `pda-048-taxa_de_resolutividade.csv`, atualização de 09/11/2026). Servem apenas
  para testar leitura, parsing e fórmulas.
- `raw/operadoras_*`: arquivos **sintéticos mínimos** (CNPJ zerado, operadora "999999" fictícia) apenas
  para exercitar o código de cobertura de chaves. **Não representam dados reais** e nunca entram em análises.
