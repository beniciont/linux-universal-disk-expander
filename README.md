# Linux Universal Disk Expander 🚀

![Version](https://img.shields.io/badge/version-3.2.0--beta-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)

Ferramenta universal e agnóstica para expansão segura de discos, partições e volumes LVM em qualquer ambiente Linux (Cloud ou On-premise). Esta branch contém a versão **v3.2.0-beta**, focada em compatibilidade **Multi-Cloud** e **Virtualização**.

## 📋 Funcionalidades em Teste (v3.2.0-beta)
- **Rescan Agnóstico**: Lógica inteligente para detectar novos espaços em **Proxmox, VMware, Hyper-V, Azure e AWS**.
- **Detecção de Ambiente**: Identifica automaticamente o provedor para aplicar o melhor método de Rescan.
- **Bus Scan SCSI**: Varredura profunda de barramentos SCSI para hipervisores locais.
- **Suporte LVM**: Detecção de espaço livre (PFree) e expansão de Logical Volumes (LVM).
- **Seleção Numérica**: Interface intuitiva para escolha de discos e partições.
- **Segurança**: Validações de kernel e sistema de arquivos antes de qualquer alteração.

## 🧪 Como Testar (Versão Beta)

Execute o comando abaixo para testar as novas funcionalidades de Rescan universal:

```bash
sudo bash -c "$(curl -sSL https://bit.ly/beniciont-linux-universal-disk-expander-develop)"
```

## 🚀 Versão Estável (v3.1.2)
Para a versão de produção, utilize:
```bash
sudo bash -c "$(curl -sSL https://bit.ly/beniciont-linux-universal-disk-expander)"
```

## 🛠️ Desenvolvimento
Para contribuir ou reportar problemas, utilize a branch de desenvolvimento (`develop`).

---
Criado por **Benicio Neto**
