# EXPANSAO OCI LINUX — oci-expand-disk.sh

[![Release](https://img.shields.io/github/v/tag/beniciont/oci-linux-disk-expander?label=release&color=2b9348)](https://github.com/beniciont/oci-linux-disk-expander/releases) [![License](https://img.shields.io/github/license/beniciont/oci-linux-disk-expander?color=blue)](LICENSE) [![Lines](https://img.shields.io/tokei/lines/github/beniciont/oci-linux-disk-expander?color=orange)](https://github.com/beniciont/oci-linux-disk-expander)

**EXPANSAO OCI LINUX**

Criado por: Benicio Neto  
Versão: 2.6.0 (PRODUÇÃO)  
Última Atualização: 03/01/2026

Um utilitário interativo para detectar e aplicar expansão de disco em instâncias Linux na OCI (Oracle Cloud Infrastructure). O script automatiza o rescan do kernel, ajuste de partições (growpart/parted), LVM e redimensionamento de sistemas de arquivos (XFS/ext4), e exibe um status final claro.

**Principais Recursos**
- Detecta espaço não alocado no disco (Espaço OCI)
- Suporte para partições padrão e LVM
- Fallbacks automáticos (growpart → parted)
- Mensagens amigáveis e log detalhado em `/var/log/oci-expand.log`
- Mensagem explícita quando a operação foi forçada mas não houve espaço (INALTERADO)

**Aviso de Segurança**
- Este script modifica partições e sistemas de arquivos. Faça backup antes de usar.
- Execute em ambientes de teste antes de produzir em produção.
- Requer `sudo` para operações de partição e redimensionamento.

---

## Como usar

1. Método recomendado (linha única):

```bash
sudo bash -c "$(curl -sSL https://bit.ly/beniciont_oci-linux-disk-expander)"
```

Observação: este comando baixa e executa o instalador diretamente. Para maior segurança, baixe o arquivo primeiro, verifique o `SHA256` e execute localmente (ex.: `sha256sum oci-expand-disk.sh`).

2. Passo a passo do fluxo interativo
- PASSO 1: Escolha o disco (ex: `sda`).
- PASSO 2: O script faz rescan do kernel e tenta detectar espaço novo.
  - Se não detectar, oferece: Rescan SCSI / Tentar de novo / Seguir mesmo assim.
  - Se você escolher `Seguir mesmo assim` e não houver espaço, o script registra que foi forçado e seguirá, mas no final mostrará `INALTERADO`.
- PASSO 3: Escolha a partição ou LV a expandir e defina tamanho (tudo ou personalizado).
- PASSO 4: O script aplica `growpart`/`parted`/`lvextend` e redimensiona o sistema de arquivos (`xfs_growfs` ou `resize2fs`).

### Novas flags (segurança e automação)

- `--dry-run`: mostra as ações que o script tomaria sem executar alterações. Útil para revisar passos antes de aplicar.
- `--force`: evita prompts de confirmação em operações não destrutivas e assume consentimento explícito; não faz operações perigosas automaticamente (ex.: `pvcreate`).

Exemplo:

```bash
sudo bash oci-expand-disk.sh --dry-run
sudo bash oci-expand-disk.sh --force
```

Observações de segurança: o modo `--force` remove prompts interativos, use apenas quando estiver seguro do ambiente; prefira `--dry-run` para validação.

3. Resultado final
- O script exibe um bloco `RESULTADO FINAL` com `STATUS:` indicando `SUCESSO`, `INALTERADO` ou erros.
- Logs adicionais em `/var/log/oci-expand.log`.

---

## Mensagens importantes
- `SUCESSO! Expansão concluída.` — operação completa e filesystem cresceu.
- `INALTERADO: ...` — operação não resultou em alteração. Pode significar:
  - Nenhum espaço físico novo disponível na OCI;
  - Você forçou a operação sem espaço (o script agora reporta isso explicitamente);
  - Comando de resize retornou `NOCHANGE`.
- `ERRO: ...` — erros técnicos traduzidos pelo script (falta de ferramentas, tamanho fora do dispositivo, etc.).

### Comportamento automático de detecção

O script agora detecta automaticamente o layout do disco e escolhe o fluxo mais seguro:

- `dm_over_disk`: detecta device-mapper/LV mapeado diretamente sobre `/dev/sdX` e, se for o caso, avalia a diferença entre o tamanho do disco físico e o LV; se o delta for insignificante (p.ex. ≤ 4 MiB) o script considera `INALTERADO` e não tenta mudanças.
- `pv_on_disk` / `pv_on_partition`: detecta PVs usados pelo LVM diretamente no disco ou em partições e lista LVs candidatos para expansão; só executa `pvresize`/`lvextend` quando um PV válido é detectado.
- `partitioned` / `raw_disk`: mantém o fluxo clássico de `growpart`/`parted` para partições padrão.

Regras de segurança implementadas:
- O script nunca executa `pvcreate` automaticamente.
- `pvresize` só é executado quando `pvs`/`pvscan` identificam claramente o PV no dispositivo alvo.
- Se não houver metadados LVM reconhecíveis, o script sugere verificar `/etc/lvm/backup` e aborta operações automáticas para evitar perda de dados.

---

## Estrutura do script (resumo técnico)
- `check_dependencies()` — tenta verificar/instalar `gdisk` quando necessário.
- `get_unallocated_space(disco)` — calcula espaço livre após a última partição usando `parted` e `lsblk`.
- `friendly_error()` — traduz saídas técnicas para mensagens legíveis.
- Fluxo interativo em 4 passos: seleção do disco → rescan → definição de partição/tamanho → execução.
- Variáveis relevantes:
  - `ESPACO_OCI` — espaço não alocado detectado em GB (float)
  - `FORCED_NO_SPACE` — flag setada quando o usuário força prosseguimento sem espaço
  - `EXP_SUCCESS` — status da operação (0 falha, 1 sucesso, 2 nochange/fallback)
  - `FINAL_MSG` — mensagem final exibida em `STATUS:` (garantida por fallback)

---

## Exemplos

- Cenário normal (disco expandido na console):
  - Execute o script, escolha disco → detectar espaço → expandir → ver `SUCESSO!`.

- Forçar sem espaço (teste de comportamento):
  - Quando o script avisar que não detectou espaço, digite `3` (Seguir mesmo assim).
  - Ao final verá `INALTERADO: Nenhuma alteração realizada — você forçou a operação mas não havia espaço livre no disco (OCI).`

---

## Troubleshooting rápido
- `Não detecta espaço mesmo após expandir na console`:
  - Use `Rescan SCSI` (opção 1 no menu) ou rode `sudo partprobe /dev/sdX`;
  - Aguarde alguns segundos e tente novamente.
- `growpart` falhou`:
  - O script tenta `parted resizepart` como fallback;
  - Verifique mensagens em `/var/log/oci-expand.log`.
- `Permissão negada`:
  - Execute com `sudo` e confirme que o usuário tem privilégios.

---

## Dicas para integrá-lo em automação
- Para executar não interativamente, adapte chamadas internas com variáveis e flags, mas atenção: operações em partições exigem validação humana.
- Se for usar via `curl | sudo bash`, sempre valide o `SHA256` antes (veja abaixo como gerar/verificar).

Se quiser apenas simular o que o script faria (recomendado antes de alterações em produção), use `--dry-run`.

---

## Verificação de integridade (opcional)
Para gerar um hash localmente antes de distribuir:

```bash
sha256sum oci-expand-disk.sh
```

Ao baixar em outra máquina, verifique o hash para garantir integridade.

Hash SHA256 (arquivo nesta versão do repositório):

```
564f2f538cbc642459b6d4cda7aedb0689c561cd65411b707958f66359e6d02d  oci-expand-disk.sh
```

Como verificar após download:

```bash
curl -sSL https://raw.githubusercontent.com/beniciont/oci-linux-disk-expander/main/oci-expand-disk.sh -o oci-expand-disk.sh
sha256sum oci-expand-disk.sh
# compare com o SHA256 acima
```

---

## Contribuição e Licença
Sinta-se à vontade para abrir issues e PRs no repositório GitHub.
Licença: ver arquivo `LICENSE` no repositório.

---
<h2 align="left">Redes Sociais</h2>

###

<div align="left">
  <a href="https://www.linkedin.com/in/benicio-neto/" target="_blank">
    <img src="https://img.shields.io/static/v1?message=LinkedIn&logo=linkedin&label=&color=0077B5&logoColor=white&labelColor=&style=for-the-badge" height="25" alt="linkedin logo"  />
  </a>
  <a href="https://medium.com/@benicio-neto" target="_blank">
    <img src="https://img.shields.io/static/v1?message=Medium&logo=medium&label=&color=12100E&logoColor=white&labelColor=&style=for-the-badge" height="25" alt="medium logo"  />
  </a>
  <a href="benicio.neto@outlook.com.br" target="_blank">
    <img src="https://img.shields.io/static/v1?message=Outlook&logo=microsoft-outlook&label=&color=0078D4&logoColor=white&labelColor=&style=for-the-badge" height="25" alt="microsoft-outlook logo"  />
  </a>
</div>

###