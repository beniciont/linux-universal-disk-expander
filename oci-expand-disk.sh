#!/bin/bash

# ==============================================================================
# LINUX UNIVERSAL DISK EXPANDER - MULTI-CLOUD & VIRTUAL
# Criado por: Benicio Neto
# Versão: 2.9.7-beta (DESENVOLVIMENTO)
# Última Atualização: 04/01/2026
#
# HISTÓRICO DE VERSÕES:
# 1.0.0 a 2.8.0 - Evolução focada em OCI.
# 2.9.0-beta (03/01/2026) - NEW: Rescan agnóstico (OCI, Azure, AWS, VirtualBox).
# 2.9.1-beta (04/01/2026) - FIX: Detecção precisa de espaço não alocado em discos RAW.
# 2.9.2-beta (04/01/2026) - FIX: Melhoria na detecção de espaço para LVM e Partições.
# 2.9.3-beta (04/01/2026) - FIX: Detecção de FSTYPE e proteção contra expansão vazia.
# 2.9.4-beta (04/01/2026) - UI: Exibir espaço não alocado no menu de aviso de rescan.
# 2.9.5-beta (04/01/2026) - FIX: Fallback de cálculo de espaço baseado no tamanho inicial.
# 2.9.6-beta (04/01/2026) - FIX: Detecção de FSTYPE via file -s e persistência de tamanho inicial.
# 2.9.7-beta (04/01/2026) - FIX: Refatoração da detecção de FSTYPE/MOUNT e debug visual.
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
    local deps=("gdisk" "util-linux" "parted" "xfsprogs" "e2fsprogs" "bc")
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

# Função para obter o espaço não alocado
get_unallocated_space() {
    local disk_name=$1
    local disk="/dev/$disk_name"
    local initial_size=$2
    
    if command -v sgdisk &>/dev/null; then
        sudo sgdisk -e "$disk" >/dev/null 2>&1
    fi

    local disk_size_bytes=$(cat "/sys/block/$disk_name/size" 2>/dev/null)
    disk_size_bytes=$((disk_size_bytes * 512))
    
    local used_bytes=0
    local has_parts=$(lsblk -ln -o TYPE "$disk" | grep -q "part" && echo "yes" || echo "no")
    
    if [[ "$has_parts" == "yes" ]]; then
        used_bytes=$(sudo parted -s "$disk" unit B print | grep -E "^ [0-9]+" | tail -n1 | awk '{print $3}' | tr -d 'B')
    else
        local pv_size=$(sudo pvs --noheadings --units b --options pv_size "$disk" 2>/dev/null | grep -oE "[0-9]+" | head -n1)
        if [[ -n "$pv_size" ]]; then
            used_bytes=$pv_size
        else
            # Fallback agressivo para RAW: Se o tamanho mudou, o usado é o inicial
            if [[ -n "$initial_size" && "$disk_size_bytes" -gt "$initial_size" ]]; then
                used_bytes=$initial_size
            else
                used_bytes=$disk_size_bytes
            fi
        fi
    fi

    local free_bytes=$((disk_size_bytes - used_bytes))
    log_message "DEBUG" "get_unallocated_space($disk): Total=$disk_size_bytes, Usado=$used_bytes, Livre=$free_bytes"

    if [[ "$free_bytes" -lt 104857600 ]]; then
        echo "0"
    else
        echo "scale=2; $free_bytes / 1024 / 1024 / 1024" | bc
    fi
}

header() {
    clear
    echo "=================================="
    echo " LINUX UNIVERSAL DISK EXPANDER v2.9.7-beta "
    echo " Criado por: Benicio Neto"
    echo " Versão: 2.9.7-beta (TESTE)"
    echo " Ambiente: Multi-Cloud / Virtual"
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
        sleep 0.1
        printf "\r               \r"
    done
    echo "  ${GREEN}[OK]${RESET} $msg"
}

# Início do Script
log_message "START" "Script Universal v2.9.7-beta iniciado."
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

    TAMANHO_INICIAL_DISCO=$(cat "/sys/block/$DISCO/size" 2>/dev/null)
    TAMANHO_INICIAL_DISCO=$((TAMANHO_INICIAL_DISCO * 512))
    TAMANHO_INICIAL_HUMANO=$(lsblk -dno SIZE "/dev/$DISCO" | head -n1 | xargs)
    
    echo -e "\n${GREEN}DISCO SELECIONADO: /dev/$DISCO ($TAMANHO_INICIAL_HUMANO)${RESET}"
    pause_nav || continue

    # PASSO 2: RESCAN AGNOSTICO
    while true; do
        header
        echo "${YELLOW}PASSO 2: Rescan do Kernel e Barramento${RESET}"
        echo "=========================="
        
        progress 2 "Atualizando Kernel via sysfs (/sys/class/block)..."
        [ -f "/sys/class/block/$DISCO/device/rescan" ] && echo 1 | sudo tee "/sys/class/block/$DISCO/device/rescan" >/dev/null 2>&1
        
        # Rescan de barramento SCSI genérico
        if [ -d "/sys/class/scsi_host" ]; then
            progress 2 "Rescan de barramento SCSI genérico..."
            for host in /sys/class/scsi_host/host*; do echo "- - -" | sudo tee "$host/scan" >/dev/null 2>&1; done
        fi

        # Rescan específico para OCI (iSCSI)
        if command -v iscsiadm &>/dev/null; then
            progress 2 "Detectado iSCSI. Executando rescan específico..."
            sudo iscsiadm -m node -R >/dev/null 2>&1 && sudo iscsiadm -m session -R >/dev/null 2>&1
        fi

        progress 2 "Sincronizando tabela de partições (partprobe)..."
        sudo partprobe "/dev/$DISCO" >/dev/null 2>&1
        
        TAMANHO_ATUAL_DISCO=$(cat "/sys/block/$DISCO/size" 2>/dev/null)
        TAMANHO_ATUAL_DISCO=$((TAMANHO_ATUAL_DISCO * 512))
        TAMANHO_ATUAL_HUMANO=$(lsblk -dno SIZE "/dev/$DISCO" | head -n1 | xargs)
        
        ESPACO_OCI=$(get_unallocated_space "$DISCO" "$TAMANHO_INICIAL_DISCO")

        if (( $(echo "$ESPACO_OCI > 0" | bc -l) )); then
            echo -e "\n${GREEN}${BOLD}SUCESSO! Espaço novo detectado.${RESET}"
            echo "Tamanho Atual: $TAMANHO_ATUAL_HUMANO"
            echo "Espaço não alocado: ${ESPACO_OCI} GB"
            pause_nav && break || continue 2
        else
            echo -e "\n${RED}AVISO: Nenhum espaço novo detectado.${RESET}"
            echo "Tamanho Atual: $TAMANHO_ATUAL_HUMANO"
            echo "Espaço não alocado calculado: ${ESPACO_OCI} GB"
            echo "--------------------------------------------------"
            echo "1) Tentar Rescan novamente"
            echo "2) Seguir mesmo assim (Forçar)"
            echo "v) Voltar ao Passo 1"
            echo "--------------------------------------------------"
            read -p "Opção: " OPT
            case $OPT in
                1) continue ;;
                2) break ;;
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

    HAS_PART=$(lsblk -ln -o TYPE "/dev/$DISCO" | grep -q "part" && echo "yes" || echo "no")
    
    if [[ "$HAS_PART" == "yes" ]]; then
        MODO="PART"
        PARTS_AVAILABLE=$(lsblk -ln -o NAME,TYPE "/dev/$DISCO" | grep "part" | awk '{print $1}')
        echo -e "\n${BLUE}Partições encontradas: $PARTS_AVAILABLE${RESET}"
        echo -n "Digite o nome da partição que deseja expandir (ex: sda3): "
        read PART_ESCOLHIDA
        
        if [[ -z "$PART_ESCOLHIDA" || ! -b "/dev/$PART_ESCOLHIDA" ]]; then
            echo "${RED}ERRO: Partição inválida!${RESET}"; sleep 2; continue
        fi
        
        ALVO_NOME="/dev/$PART_ESCOLHIDA"
        PART_NUM=$(echo "$PART_ESCOLHIDA" | grep -oE "[0-9]+$" | tail -1)
        MOUNT=$(lsblk -no MOUNTPOINT "$ALVO_NOME" | grep -v "^$" | head -n1 | xargs)
        TYPE=$(lsblk -no FSTYPE "$ALVO_NOME" | grep -v "^$" | head -n1 | xargs)
        [[ -z "$TYPE" ]] && TYPE=$(sudo blkid -o value -s TYPE "$ALVO_NOME")
        [[ -z "$MOUNT" ]] && MOUNT=$(grep "^$ALVO_NOME " /proc/mounts | awk '{print $2}')
        [[ -z "$TYPE" ]] && TYPE=$(grep "^$ALVO_NOME " /proc/mounts | awk '{print $3}')
        
        if lsblk -no FSTYPE "$ALVO_NOME" | grep -qi "LVM"; then
            HAS_LVM="yes"
            REAL_LV=$(lsblk -ln -o NAME,TYPE "$ALVO_NOME" | grep "lvm" | head -n1 | awk '{print $1}')
            [[ -n "$REAL_LV" ]] && ALVO_LVM="/dev/mapper/$REAL_LV" || ALVO_LVM=""
        else
            HAS_LVM="no"
            ALVO_LVM=""
        fi
    else
        MODO="RAW"
        ALVO_NOME="/dev/$DISCO"
        MOUNT=$(lsblk -no MOUNTPOINT "$ALVO_NOME" | grep -v "^$" | head -n1 | xargs)
        TYPE=$(lsblk -no FSTYPE "$ALVO_NOME" | grep -v "^$" | head -n1 | xargs)
        [[ -z "$TYPE" ]] && TYPE=$(sudo blkid -o value -s TYPE "$ALVO_NOME")
        [[ -z "$MOUNT" ]] && MOUNT=$(grep "^$ALVO_NOME " /proc/mounts | awk '{print $2}')
        [[ -z "$TYPE" ]] && TYPE=$(grep "^$ALVO_NOME " /proc/mounts | awk '{print $3}')
        
        # Terceira tentativa de detecção de FSTYPE para RAW via file -s
        if [[ -z "$TYPE" ]]; then
            local file_out=$(sudo file -s "$ALVO_NOME")
            if echo "$file_out" | grep -qi "ext4"; then TYPE="ext4";
            elif echo "$file_out" | grep -qi "xfs"; then TYPE="xfs"; fi
        fi

        if lsblk -no FSTYPE "$ALVO_NOME" | grep -qi "LVM"; then
            HAS_LVM="yes"
            REAL_LV=$(lsblk -ln -o NAME,TYPE "$ALVO_NOME" | grep "lvm" | head -n1 | awk '{print $1}')
            [[ -n "$REAL_LV" ]] && ALVO_LVM="/dev/mapper/$REAL_LV" || ALVO_LVM=""
        else
            HAS_LVM="no"
            ALVO_LVM=""
        fi
    fi
    
    echo -e "${CYAN}DEBUG: Alvo=$ALVO_NOME | Mount=$MOUNT | Type=$TYPE${RESET}"

    FINAL_TARGET="${ALVO_LVM:-$ALVO_NOME}"
    
    if [[ -n "$MOUNT" && "$MOUNT" != "" ]]; then
        FS_SIZE_BEFORE=$(df -B1 "$MOUNT" | tail -n1 | awk '{print $2}')
    else
        FS_SIZE_BEFORE=$(lsblk -bdno SIZE "$FINAL_TARGET" | head -n1)
    fi

    # ESCOLHA DO TAMANHO DA EXPANSAO
    echo -e "\n${YELLOW}OPÇÕES DE EXPANSÃO:${RESET}"
    echo "1) Usar todo o espaço disponível (100%)"
    echo "2) Definir um valor específico (ex: 10G, 500M)"
    echo -n "Escolha uma opção: "
    read OPT_SIZE
    
    EXP_VALUE=""
    if [[ "$OPT_SIZE" == "2" ]]; then
        echo -n "Digite o valor desejado (ex: 10G, 500M): "
        read EXP_VALUE
        if [[ ! "$EXP_VALUE" =~ ^[0-9]+[GgMm]$ ]]; then
            echo "${RED}ERRO: Formato inválido! Use algo como 10G ou 500M.${RESET}"; sleep 2; continue
        fi
    fi

    echo -e "\n${BLUE}Confirmar expansão de $FINAL_TARGET? (s/n)${RESET}"
    read CONFIRM
    [[ ${CONFIRM,,} != 's' ]] && continue

    # PASSO 4: EXECUÇÃO
    header
    echo "${GREEN}PASSO 4: Executando Expansão Universal${RESET}"
    echo "================================"
    
    if [[ "$MODO" == "PART" ]]; then
        progress 2 "Expandindo partição $PART_NUM..."
        if [[ -z "$EXP_VALUE" ]]; then
            sudo growpart "/dev/$DISCO" "$PART_NUM" >/dev/null 2>&1 || sudo parted -s "/dev/$DISCO" resizepart "$PART_NUM" 100% >/dev/null 2>&1
        else
            sudo parted -s "/dev/$DISCO" resizepart "$PART_NUM" "$EXP_VALUE" >/dev/null 2>&1
        fi
        sudo partprobe "/dev/$DISCO" >/dev/null 2>&1
    fi

    if [[ "$HAS_LVM" == "yes" ]]; then
        progress 2 "Redimensionando Physical Volume (PV)..."
        PV_TARGET=$(pvs --noheadings -o pv_name | grep "$DISCO" | head -n1 | xargs)
        [[ -z "$PV_TARGET" ]] && PV_TARGET="$ALVO_NOME"
        sudo pvresize "$PV_TARGET" >/dev/null 2>&1
        
        if [[ -n "$ALVO_LVM" ]]; then
            if [[ -z "$EXP_VALUE" ]]; then
                progress 2 "Expandindo Logical Volume (LV) ao máximo..."
                sudo lvextend -l +100%FREE "$ALVO_LVM" >/dev/null 2>&1
            else
                progress 2 "Expandindo Logical Volume (LV) em $EXP_VALUE..."
                sudo lvextend -L +"$EXP_VALUE" "$ALVO_LVM" >/dev/null 2>&1
            fi
        fi
    fi

    if [[ -n "$MOUNT" && "$MOUNT" != "" ]]; then
        if [[ -n "$TYPE" ]]; then
            progress 2 "Expandindo Sistema de Arquivos ($TYPE) em $MOUNT..."
            case "$TYPE" in
                xfs) sudo xfs_growfs "$MOUNT" >/dev/null 2>&1 ;;
                ext*) sudo resize2fs "$FINAL_TARGET" >/dev/null 2>&1 ;;
                btrfs) sudo btrfs filesystem resize max "$MOUNT" >/dev/null 2>&1 ;;
                *) log_message "WARN" "Tipo de FS ($TYPE) não suportado para expansão automática." ;;
            esac
        else
            echo "${RED}ERRO: Não foi possível detectar o tipo de sistema de arquivos em $MOUNT!${RESET}"
            log_message "ERROR" "FSTYPE não detectado para $FINAL_TARGET"
        fi
    fi

    if [[ -n "$MOUNT" && "$MOUNT" != "" ]]; then
        FS_SIZE_AFTER=$(df -B1 "$MOUNT" | tail -n1 | awk '{print $2}')
    else
        FS_SIZE_AFTER=$(lsblk -bdno SIZE "$FINAL_TARGET" | head -n1)
    fi

    header
    echo "${GREEN}RESULTADO FINAL${RESET}"
    echo "=================="
    if [[ -n "$MOUNT" && "$MOUNT" != "" ]]; then
        df -h "$MOUNT"
    else
        lsblk "$FINAL_TARGET"
    fi
    
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
