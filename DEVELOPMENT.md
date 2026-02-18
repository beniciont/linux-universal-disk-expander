# Guia de Desenvolvimento e Testes 🛠️

Este arquivo descreve o fluxo de trabalho para novas funcionalidades e o estado atual da branch de desenvolvimento (`develop`).

## 🚀 Versão em Teste: v3.2.9-beta

### Objetivo
Tornar o script **Universal e Agnóstico**, permitindo a expansão de discos em qualquer ambiente Linux, independentemente do hipervisor ou nuvem.

### Funcionalidades em Validação
- [x] **Rescan SCSI Genérico:** Testado em Proxmox, VMware e VirtualBox.
- [x] **Detecção Inteligente de iSCSI:** Garantir que comandos OCI só rodem se o `iscsiadm` estiver presente.
- [x] **Compatibilidade Multi-Cloud:** Validar rescan em instâncias Azure e AWS.
- [x] **Prioridade growpart**: O script agora prioriza o uso do `growpart` para expansão de partições, com fallback para `parted`.
- [x] **Correção EXT4**: Melhoria na lógica de redimensionamento online para sistemas de arquivos EXT4.

---

## 🧪 Como Testar esta Versão
Para rodar a versão de desenvolvimento diretamente em um ambiente de teste:

```bash
sudo bash -c "$(curl -sSL https://bit.ly/beniciont-linux-universal-disk-expander-develop)"
```

---

## 🔄 Fluxo de Trabalho (Git Flow)
1. **Desenvolvimento:** Todas as novas ideias entram primeiro na branch de desenvolvimento (`develop`).
2. **Testes:** Validação em diferentes ambientes (Cloud, On-premise).
3. **Homologação:** Após sucesso nos testes, o código é revisado.
4. **Produção:** Merge da `develop` para a `main` e criação de uma nova Tag/Release.

---

## 🐛 Reportando Problemas
Se encontrar um bug nesta versão beta, por favor, abra uma Issue/Problema no GitHub detalhando:
- O ambiente (ex: Proxmox 8.1).
- O erro apresentado.
- O log gerado em `/var/log/linux-disk-expander.log`.

---
**Mantido por:** [Benicio Neto](https://github.com/beniciont)
