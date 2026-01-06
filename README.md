# Linux Universal Disk Expander 🚀

![Version](https://img.shields.io/badge/version-3.1.2-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)

Ferramenta universal para expansão segura de discos, partições e volumes LVM em ambientes de nuvem (OCI, AWS, Azure, GCP) e virtualização.

## 📋 Funcionalidades (v3.1.2 Estável)
- **Rescan Inteligente**: Atualiza barramentos SCSI e sessões iSCSI automaticamente.
- **Suporte LVM**: Detecção de espaço livre (PFree) e expansão de Logical Volumes.
- **Seleção Numérica**: Interface intuitiva para escolha de discos e partições.
- **Segurança**: Validações de kernel e sistema de arquivos antes de qualquer alteração.

## 🚀 Como Usar (Versão Estável)

Execute o comando abaixo como root:

```bash
sudo bash -c "\$(curl -sSL https://bit.ly/beniciont-linux-universal-disk-expander)"
```

## 🛠️ Desenvolvimento
Para testar novas funcionalidades (NVMe, LUKS), utilize a branch \`develop\`:
\`https://bit.ly/beniciont-linux-universal-disk-expander-develop\`

---
Criado por **Benicio Neto**
