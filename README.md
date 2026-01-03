# OCI Linux Disk Expander 🚀

[![Release](https://img.shields.io/github/v/tag/beniciont/oci-linux-disk-expander?label=release&color=2b9348)](https://github.com/beniciont/oci-linux-disk-expander/releases) [![License](https://img.shields.io/github/license/beniciont/oci-linux-disk-expander?color=blue)](LICENSE)

Script automatizado para expansão de discos e partições em instâncias Linux na Oracle Cloud Infrastructure (OCI). Projetado para ser seguro, interativo e flexível.

---

## 🌟 Novidades da Versão 2.5.7
- **Flexibilidade Total:** Agora permite forçar a expansão mesmo quando o Kernel não detecta o espaço automaticamente (útil para casos de "teimosia" do sistema).
- **Precisão de Bytes:** Comparação exata de bytes (antes vs depois) para garantir que a expansão realmente ocorreu.
- **Feedback Visual Aprimorado:** Mensagens de status claras e destacadas (Sucesso ou Inalterado).
- **Execução Remota:** Comando otimizado para execução direta via `curl` sem necessidade de download manual.

---

## 🚀 Como Executar (One-Liner)

Para rodar o script instantaneamente sem baixar arquivos:

```bash
sudo bash -c "$(curl -sSL https://raw.githubusercontent.com/beniciont/oci-linux-disk-expander/main/oci-expand-disk.sh)"
```

---

## 🛠️ Funcionalidades
- **Rescan Automático:** Executa rescan de barramento SCSI, iSCSI (OCI) e atualiza o Kernel via sysfs.
- **Suporte LVM e Partição Padrão:** Detecta automaticamente se o disco usa LVM ou partições simples.
- **Segurança em Primeiro Lugar:**
  - Captura o tamanho exato em bytes antes de iniciar.
  - Avisa se não detectar espaço livre, mas permite que o administrador decida prosseguir.
  - Logs detalhados em `/var/log/oci-expand.log`.
- **Tradução de Erros:** Transforma mensagens técnicas complexas em avisos compreensíveis.

---

## 📖 Passo a Passo de Uso
1. **Seleção do Disco:** O script lista os discos disponíveis para você escolher.
2. **Rescan do Kernel:** Tentativa automática de detectar o novo tamanho expandido na console OCI.
3. **Definição de Tamanho:** Escolha entre usar todo o espaço novo ou um valor personalizado (ex: +5G).
4. **Execução:** O script realiza os comandos (`growpart`, `lvextend`, `xfs_growfs`, `resize2fs`) conforme a estrutura detectada.
5. **Resultado:** Exibição clara se a operação foi um **SUCESSO** ou se o disco permaneceu **INALTERADO**.

---

## 📋 Requisitos
- Sistema Operacional Linux (Oracle Linux, Ubuntu, CentOS, RHEL).
- Privilégios de `sudo`.
- Ferramentas básicas: `curl`, `lsblk`, `parted`, `gdisk` (o script tenta instalar se faltar).

---

## 📝 Logs e Auditoria
Todas as operações são registradas para sua segurança:
- Arquivo: `/var/log/oci-expand.log`
- Níveis: `INFO`, `EXEC`, `SUCCESS`, `WARN`, `ERROR`.

---

## 🤝 Contribuição e Licença
Sinta-se à vontade para abrir issues e Pull Requests.
Criado por: **Benicio Neto**

<h2 align="left">Conecte-se comigo</h2>
<div align="left">
  <a href="https://www.linkedin.com/in/benicio-neto/" target="_blank">
    <img src="https://img.shields.io/static/v1?message=LinkedIn&logo=linkedin&label=&color=0077B5&logoColor=white&labelColor=&style=for-the-badge" height="25" alt="linkedin logo"  />
  </a>
  <a href="https://medium.com/@benicio-neto" target="_blank">
    <img src="https://img.shields.io/static/v1?message=Medium&logo=medium&label=&color=12100E&logoColor=white&labelColor=&style=for-the-badge" height="25" alt="medium logo"  />
  </a>
</div>
