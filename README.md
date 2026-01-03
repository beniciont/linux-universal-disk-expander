# OCI Linux Disk Expander 🚀 (Branch: develop)

> [!WARNING]
> **ESTA É UMA VERSÃO DE DESENVOLVIMENTO (BETA).**
> Use apenas para testes. Para produção, utilize a [branch main](https://github.com/beniciont/oci-linux-disk-expander/tree/main).

[![Release](https://img.shields.io/github/v/release/beniciont/oci-linux-disk-expander?color=green&label=Release)](https://github.com/beniciont/oci-linux-disk-expander/releases)
[![License](https://img.shields.io/github/license/beniciont/oci-linux-disk-expander?color=blue)](LICENSE)

Ferramenta universal para expansão de discos e partições em instâncias Linux na **Oracle Cloud Infrastructure (OCI)**. Desenvolvida para simplificar o processo de redimensionamento de volumes, suportando desde discos simples até estruturas complexas de LVM.

---

## 🌟 Funcionalidades (v2.8.0)

- **Detecção Universal:** Identifica automaticamente discos Raw, Particionados e LVM.
- **Expansão Personalizada:** Escolha entre expandir 100% do espaço ou definir um valor específico (ex: 10G, 500M).
- **Precisão de Setores:** Leitura direta do Kernel (`/sys/block`) para garantir que o espaço livre exibido seja real.
- **Suporte a File Systems:** Compatível com **XFS**, **EXT4** e **BTRFS**.
- **Segurança:** Verificação de bytes antes e depois da operação para confirmar o sucesso real.
- **Rescan Automático:** Executa rescan de barramento iSCSI e Kernel automaticamente.

---

## 🚀 Como Usar (Execução Rápida)

Execute o comando abaixo como **root** para iniciar a ferramenta sem precisar baixar arquivos manualmente:

```bash
sudo bash -c "$(curl -sSL https://raw.githubusercontent.com/beniciont/oci-linux-disk-expander/develop/oci-expand-disk.sh)"
```



---

## 🛠️ Estruturas Suportadas

| Tipo de Disco | Estrutura | Ação do Script |
| :--- | :--- | :--- |
| **Particionado** | sda1, sda2, sda3 | Expande a partição e o Sistema de Arquivos. |
| **Raw Disk** | sdb, sdc (sem partições) | Expande o Sistema de Arquivos diretamente no disco. |
| **LVM (Partição)** | sda3 -> PV -> VG -> LV | Expande Partição -> PV -> LV -> Sistema de Arquivos. |
| **LVM (Raw)** | sdb -> PV -> VG -> LV | Expande PV -> LV -> Sistema de Arquivos. |

---

## 📝 Logs e Auditoria

Todas as operações são registradas para sua segurança:
- **Arquivo de Log:** `/var/log/oci-expand.log`
- **Níveis de Log:** INFO, EXEC, DEBUG e WARN.

---

## 👨‍💻 Autor

**Benicio Neto**
- GitHub: [@beniciont](https://github.com/beniciont)
- LinkedIn: [Benicio Neto](https://www.linkedin.com/in/benicioneto/)

---

## 📄 Licença

Este projeto está sob a licença MIT. Veja o arquivo [LICENSE](LICENSE) para mais detalhes.
