# Linux Universal Disk Expander 🚀

![Version](https://img.shields.io/badge/version-3.2.9-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)

Ferramenta universal e agnóstica para expansão segura de discos, partições e volumes LVM em qualquer ambiente Linux (Cloud ou On-premise). Esta branch contém a versão **v3.2.9**, que é a versão estável, focada em compatibilidade **Multi-Cloud** e **Virtualização**.

## ✨ Funcionalidades Principais (v3.2.9)
- **Rescan Agnóstico**: Lógica inteligente para detectar novos espaços em **Proxmox, VMware, Hyper-V, Azure e AWS**.
- **Detecção de Ambiente**: Identifica automaticamente o provedor para aplicar o melhor método de Rescan.
- **Bus Scan SCSI**: Varredura profunda de barramentos SCSI para hipervisores locais.
- **Suporte LVM**: Detecção de espaço livre (PFree) e expansão de Logical Volumes (LVM).
- **Seleção Numérica**: Interface intuitiva para escolha de discos e partições.
- **Segurança**: Validações de kernel e sistema de arquivos antes de qualquer alteração.
- **Prioridade growpart**: O script agora prioriza o uso do `growpart` para expansão de partições, com fallback para `parted`.
- **Correção EXT4**: Melhoria na lógica de redimensionamento online para sistemas de arquivos EXT4.

## 🚀 Como Usar (Versão Estável)

Execute o comando abaixo para utilizar a versão estável:

```bash
sudo bash -c "$(curl -sSL https://bit.ly/beniciont-linux-universal-disk-expander)"
```

## 🛠️ Desenvolvimento
Para contribuir ou reportar problemas, utilize a branch de desenvolvimento (`develop`).

---
Criado por **Benicio Neto**
