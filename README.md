# OCI Linux Disk Expander 🚀 (Branch: develop)

> [!WARNING]
> **ESTA É UMA VERSÃO DE DESENVOLVIMENTO (BETA).**
> Use apenas para testes. Para produção, utilize a [branch main](https://github.com/beniciont/oci-linux-disk-expander/tree/main).

[![Release](https://img.shields.io/github/v/release/beniciont/oci-linux-disk-expander?color=orange&label=Beta)](https://github.com/beniciont/oci-linux-disk-expander/tree/develop)
[![License](https://img.shields.io/github/license/beniciont/oci-linux-disk-expander?color=blue)](LICENSE)

Ferramenta universal para expansão de discos e partições em instâncias Linux. Esta branch contém a versão **v2.9.0-beta**, focada em compatibilidade **Multi-Cloud** e **Virtualização**.

---

## 🌟 Funcionalidades em Teste (v2.9.0-beta)

- **Rescan Agnóstico:** Lógica inteligente para detectar novos espaços em **Proxmox, VMware, Hyper-V, Azure e AWS**.
- **Detecção de Ambiente:** Identifica automaticamente se está em OCI ou outros provedores para aplicar o melhor método de rescan.
- **Bus Scan SCSI:** Varredura profunda de barramentos SCSI para hipervisores locais.
- **Tudo da v2.8.0:** Inclui todas as melhorias de expansão personalizada e precisão de setores.

---

## 🧪 Como Testar (Execução Beta)

Execute o comando abaixo para testar as novas funcionalidades de rescan universal:

```bash
sudo bash -c "$(curl -sSL https://raw.githubusercontent.com/beniciont/oci-linux-disk-expander/develop/oci-expand-disk.sh)"
```

---

## 🛠️ Suporte Experimental

| Ambiente | Status | Método de Rescan |
| :--- | :--- | :--- |
| **Oracle Cloud (OCI)** | ✅ Estável | iSCSI + sysfs |
| **Proxmox / KVM** | 🧪 Beta | SCSI Bus Scan |
| **VMware / VirtualBox** | 🧪 Beta | SCSI Bus Scan + sysfs |
| **Azure / AWS** | 🧪 Beta | sysfs + sgdisk |

---

## 📝 Documentação de Desenvolvimento

Para detalhes técnicos sobre como contribuir ou o que está sendo testado, veja o arquivo [DEVELOPMENT.md](DEVELOPMENT.md).

---

## 👨‍💻 Autor

**Benicio Neto**
- GitHub: [@beniciont](https://github.com/beniciont)
- LinkedIn: [Benicio Neto](https://www.linkedin.com/in/benicioneto/)

---

## 📄 Licença

Este projeto está sob a licença MIT. Veja o arquivo [LICENSE](LICENSE) para mais detalhes.
