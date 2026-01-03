#!/bin/bash

# ==============================================================================
# EXPANSAO OCI LINUX - FERRAMENTA UNIVERSAL
# Criado por: Benicio Neto
# Versão: 2.7.0 (PRODUÇÃO)
# Última Atualização: 03/01/2026
#
# HISTÓRICO DE VERSÕES:
# 1.0.0 a 2.6.0 - Evolução e suporte a discos Raw.
# 2.7.0 (03/01/2026) - UNIVERSAL: Suporte completo a Raw, Partições, LVM e FS.
# ==============================================================================

# Configurações de Log
LOG_FILE="/var/log/oci-expand.log"
USER_EXEC=$(whoami)

# Cores seguras com tput
RED=$(tput setaf 1 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
BLUE=$(tput setaf 4 2>/dev/null || true)
CYAN=$(tput setaf 6 2>/dev/null || true)
BOLD=$(tput bold 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

# Função de Log
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    if [ ! -f "$LOG_FILE" ]; then
        sudo touch "$LOG_FILE" 2>/dev/null
        sudo chmod 664 "$LOG_FILE" 2>/dev/null
        sudo chown root:adm "$LOG_FILE" 2>/dev/null
    fi

    echo "[$timestamp] [$level] [User: $USER_EXEC] - $message" | sudo tee -a "$LOG_FILE" >/dev/null 2>&1
}

# Função para instalar dependências
check_dependencies() {
    local deps=("gdisk" "util-linux" "parted" "xfsprogs" "e2fsprogs")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null && [[ "$dep" != "util-linux" ]]; then
            log_message "INFO" "$dep não encontrado. Tentando instalar..."
            if command -v yum &>/dev/null; then
                sudo yum install -y "$dep" >/dev/null 2>&1
            elif command -v apt-get &>/dev/null; then
                sudo apt-get update >/dev/null 2>&1
                sudo apt-get install -y "$dep" >/dev/null 2>&1
            fi
        fi
    done
}

# Função para traduzir e padronizar erros
friendly_error() {
    local raw_msg="$1"
    if echo "$raw_msg" | grep -qiE "matches existing size|nothing to do|NOCHANGE"; then
        echo "INALTERADO: O volume já possui o tamanho solicitado ou não há novo espaço."
    elif echo "$raw_msg" | grep -qiE "insufficient free space|not enough free space"; then
        echo "ERRO: Não há espaço livre disponível no disco físico para esta expansão."
    elif echo "$raw_msg" | grep -qi "being used"; then
        echo "" # Silenciamos avisos de uso
    else
        echo "ERRO TÉCNICO: $raw_msg"
    fi
}

# Função para obter o espaço não alocado (Espaço OCI)
get_unallocated_space() {
    local disk="/dev/$1"
    check_dependencies
    if command -v sgdisk &>/dev/null; then sudo sgdisk -e "$disk" >/dev/null 2>&1; fi

    local disk_size_bytes=$(lsblk -bdno SIZE "$disk" | head -n1 | tr -d ' ')
    local last_part_end=$(sudo parted -s "$disk" unit B print | grep -E "^ [0-9]+" | tail -n1 | awk '{print $3}' | tr -d 'B')
    
    if [[ -z "$last_part_end" ]]; then
        echo "scale=2; $disk_size_bytes / 1024 / 1024 / 1024" | bc
    else
        local free_bytes=$((disk_size_bytes - last_part_end))
        if [[ "$free_bytes" -lt 1048576 ]]; then echo "0"; else echo "scale=2; $free_bytes / 1024 / 1024 / 1024" | bc; fi
    fi
}

header() {
    clear
    echo "=================================="
    echo " EXPANSAO OCI LINUX v2.7.0 "
    echo " Criado por: Benicio Neto"
    echo " Versão: 2.7.0 (UNIVERSAL)"
    echo " Última Atualização: 03/01/2026 "
    echo "=================================="
    echo
}

pause_nav() {
    echo
    echo -n "${YELLOW}[ENTER] continuar (v=voltar / q=sair): ${RESET}"
    read resp
    case ${resp,,} in
        'q') exit 0 ;;
        'v') return 1 ;;
        *) return 0 ;;
    esac
}

progress() {
    local steps=$1 msg=$2
    echo "  > $msg"
    log_message "EXEC" "$msg"
    for ((i=1; i<=steps; i++)); do
        printf "    [%3d%%] " $((i*100/steps))
        sleep 0.3
        printf "\r               \r"
    done
    echo "  ${GREEN}[OK]${RESET} $msg"
}

# Início do Script
log_message "START" "Script Universal iniciado."
check_dependencies

while true; do
    # PASSO 1: ESCOLHA DO DISCO
    header
    echo "${YELLOW}PASSO 1: Escolha o disco físico${RESET}"
    echo "=========================="
    lsblk -d -n -o NAME,SIZE,TYPE,MODEL | grep "disk"
    echo "=========================="
    echo -n "${BLUE}Digite o nome do disco (ex: sda, sdb): ${RESET}"
    read DISCO
    
    [[ ${DISCO,,} == 'q' ]] && exit 0
    if [[ -z "$DISCO" || ! -b "/dev/$DISCO" ]]; then
        echo "${RED}ERRO: Disco /dev/$DISCO não encontrado!${RESET}"; sleep 2; continue
    fi

    TAMANHO_ANTIGO=$(lsblk -bdno SIZE "/dev/$DISCO" | head -n1 | tr -d ' ')
    TAMANHO_ANTIGO_HUMANO=$(lsblk -dno SIZE "/dev/$DISCO" | head -n1)
    echo -e "\n${GREEN}DISCO SELECIONADO: /dev/$DISCO ($TAMANHO_ANTIGO_HUMANO)${RESET}"
    pause_nav || continue

    # PASSO 2: RESCAN
    while true; do
        header
        echo "${YELLOW}PASSO 2: Rescan do Kernel e Barramento${RESET}"
        echo "=========================="
        progress 2 "Atualizando /sys/class/block/$DISCO..."
        [ -f "/sys/class/block/$DISCO/device/rescan" ] && echo 1 | sudo tee "/sys/class/block/$DISCO/device/rescan" >/dev/null 2>&1
        progress 2 "Rescan iSCSI OCI..."
        sudo iscsiadm -m node -R >/dev/null 2>&1 && sudo iscsiadm -m session -R >/dev/null 2>&1
        progress 2 "Sincronizando partições..."
        sudo partprobe "/dev/$DISCO" >/dev/null 2>&1
        
        TAMANHO_NOVO=$(lsblk -bdno SIZE "/dev/$DISCO" | head -n1 | tr -d ' ')
        TAMANHO_NOVO_HUMANO=$(lsblk -dno SIZE "/dev/$DISCO" | head -n1)
        ESPACO_OCI=$(get_unallocated_space "$DISCO")

        if [ "$TAMANHO_NOVO" -gt "$TAMANHO_ANTIGO" ] || (( $(echo "$ESPACO_OCI > 0" | bc -l) )); then
            echo -e "\n${GREEN}SUCESSO! Espaço novo detectado.${RESET}"
            echo "Tamanho: $TAMANHO_NOVO_HUMANO | Livre (OCI): ${ESPACO_OCI} GB"
            pause_nav && break || continue 2
        else
            echo -e "\n${RED}AVISO: O tamanho do disco não mudou ($TAMANHO_NOVO_HUMANO).${RESET}"
            echo "1) Rescan SCSI  2) Tentar de novo  3) Seguir mesmo assim  v) Voltar"
            read -p "Opção: " OPT
            case $OPT in
                1) sudo rescan-scsi-bus.sh 2>/dev/null; continue ;;
                3) break ;;
                v) continue 2 ;;
                *) continue ;;
            esac
        fi
    done

    # PASSO 3: DETECÇÃO UNIVERSAL
    header
    echo "${CYAN}PASSO 3: Estrutura Detectada${RESET}"
    echo "======================"
    lsblk "/dev/$DISCO" -o NAME,FSTYPE,SIZE,MOUNTPOINT,TYPE
    echo "======================"

    # Identificação de Cenário
    HAS_PART=$(lsblk -ln -o TYPE "/dev/$DISCO" | grep -q "part" && echo "yes" || echo "no")
    HAS_LVM=$(lsblk -ln -o FSTYPE "/dev/$DISCO" | grep -qi "LVM" && echo "yes" || echo "no")
    
    if [[ "$HAS_LVM" == "yes" ]]; then
        MODO="LVM"
        # Pega o LV que tem ponto de montagem, priorizando a raiz /
        ALVO_NOME=$(lsblk -ln -o NAME,MOUNTPOINT "/dev/$DISCO" | grep "lvm" | sort -k2 -r | head -n1 | awk '{print "/dev/mapper/"$1}')
        MOUNT=$(lsblk -no MOUNTPOINT "$ALVO_NOME" | head -n1)
        TYPE=$(lsblk -no FSTYPE "$ALVO_NOME" | head -n1)
        echo -e "${YELLOW}CENÁRIO: LVM Detectado ($ALVO_NOME)${RESET}"
    elif [[ "$HAS_PART" == "yes" ]]; then
        MODO="PART"
        PART_NOME=$(lsblk -ln -o NAME,MOUNTPOINT "/dev/$DISCO" | grep "part" | sort -k2 -r | head -n1 | awk '{print $1}')
        ALVO_NOME="/dev/$PART_NOME"
        PART_NUM=$(echo "$PART_NOME" | grep -oE "[0-9]+$" | tail -1)
        MOUNT=$(lsblk -no MOUNTPOINT "$ALVO_NOME" | head -n1)
        TYPE=$(lsblk -no FSTYPE "$ALVO_NOME" | head -n1)
        echo -e "${YELLOW}CENÁRIO: Partição Padrão Detectada ($ALVO_NOME)${RESET}"
    else
        MODO="RAW"
        ALVO_NOME="/dev/$DISCO"
        MOUNT=$(lsblk -no MOUNTPOINT "$ALVO_NOME" | head -n1)
        TYPE=$(lsblk -no FSTYPE "$ALVO_NOME" | head -n1)
        echo -e "${YELLOW}CENÁRIO: Disco Raw (Sem Partição) Detectado${RESET}"
    fi

    # Captura tamanho inicial para comparação final
    [[ -n "$MOUNT" ]] && FS_SIZE_BEFORE=$(df -B1 "$MOUNT" | tail -n1 | awk '{print $2}') || FS_SIZE_BEFORE=$(lsblk -bdno SIZE "$ALVO_NOME" | head -n1)

    echo -e "\n${BLUE}Deseja expandir $ALVO_NOME usando todo o espaço disponível? (s/n)${RESET}"
    read CONFIRM
    [[ ${CONFIRM,,} != 's' ]] && continue

    # PASSO 4: EXECUÇÃO UNIVERSAL
    header
    echo "${GREEN}PASSO 4: Executando Expansão Universal${RESET}"
    echo "================================"
    
    # 1. Expandir o recipiente (Partição ou PV)
    if [[ "$MODO" == "PART" ]]; then
        progress 2 "Expandindo partição $PART_NUM..."
        sudo growpart "/dev/$DISCO" "$PART_NUM" >/dev/null 2>&1 || sudo parted -s "/dev/$DISCO" resizepart "$PART_NUM" 100% >/dev/null 2>&1
        sudo partprobe "/dev/$DISCO" >/dev/null 2>&1
    fi

    if [[ "$HAS_LVM" == "yes" ]]; then
        progress 2 "Redimensionando Physical Volume (PV)..."
        # PV pode estar no disco ou na partição
        PV_TARGET=$(pvs --noheadings -o pv_name | grep "$DISCO" | head -n1 | xargs)
        sudo pvresize "$PV_TARGET" >/dev/null 2>&1
        progress 2 "Expandindo Logical Volume (LV)..."
        sudo lvextend -l +100%FREE "$ALVO_NOME" >/dev/null 2>&1
    fi

    # 2. Expandir o Sistema de Arquivos
    if [[ -n "$MOUNT" ]]; then
        progress 2 "Expandindo Sistema de Arquivos ($TYPE)..."
        case "$TYPE" in
            xfs) sudo xfs_growfs "$MOUNT" >/dev/null 2>&1 ;;
            ext*) sudo resize2fs "$ALVO_NOME" >/dev/null 2>&1 ;;
            btrfs) sudo btrfs filesystem resize max "$MOUNT" >/dev/null 2>&1 ;;
        esac
    fi

    # Verificação Final
    [[ -n "$MOUNT" ]] && FS_SIZE_AFTER=$(df -B1 "$MOUNT" | tail -n1 | awk '{print $2}') || FS_SIZE_AFTER=$(lsblk -bdno SIZE "$ALVO_NOME" | head -n1)

    header
    echo "${GREEN}RESULTADO FINAL${RESET}"
    echo "=================="
    df -h "$MOUNT" 2>/dev/null || lsblk "$ALVO_NOME"
    
    echo -e "\n--------------------------------------------------"
    if [[ "$FS_SIZE_AFTER" -gt "$FS_SIZE_BEFORE" ]]; then
        echo -e "STATUS: ${GREEN}${BOLD}SUCESSO! Expansão concluída.${RESET}"
    else
        echo -e "STATUS: ${YELLOW}${BOLD}INALTERADO: O tamanho não mudou.${RESET}"
    fi
    echo -e "--------------------------------------------------"
    
    pause_nav || continue
    exit 0
done
