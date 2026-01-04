#!/bin/bash

# ==============================================================================
# LINUX UNIVERSAL DISK EXPANDER - MULTI-CLOUD & VIRTUAL
# Criado por: Benicio Neto
# Versão: 3.0.4 (ESTÁVEL)
# Última Atualização: 04/01/2026
#
# HISTÓRICO DE VERSÕES:
# 1.0.0 a 2.8.0 - Evolução focada em OCI.
# 2.9.x-beta    - Rescan agnóstico, correções de RAW e LVM no Azure.
# 3.0.0         - NEW: Interface profissional, menus numerados, resumo Antes/Depois.
# 3.0.1         - FIX: Lógica de listagem de discos mais robusta para diferentes ambientes.
# 3.0.2         - FIX: Validação de espaço real e verificação de alteração pós-expansão.
# 3.0.3         - FIX: Cálculo real de nova capacidade e trava de sanidade bloqueante.
# 3.0.4         - UI: Melhoria na semântica das mensagens de aviso e fluxo de expansão.
# ==============================================================================

# Configurações de Log
LOG_FILE="/var/log/oci-expand.log"
USER_EXEC=$(whoami)

# Cores e Estilos
RED=$(tput setaf 1 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
BLUE=$(tput setaf 4 2>/dev/null || true)
CYAN=$(tput setaf 6 2>/dev/null || true)
MAGENTA=$(tput setaf 5 2>/dev/null || true)
BOLD=$(tput bold 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

# Ícones
ICON_DISK="📦"
ICON_PART="📂"
ICON_LVM="🗄️"
ICON_INFO="ℹ️"
ICON_SUCCESS="✅"
ICON_WARN="⚠️"
ICON_ERROR="❌"

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
    local deps=("gdisk" "util-linux" "parted" "xfsprogs" "e2fsprogs" "bc" "file")
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
        if sudo parted -s "$disk" print 2>/dev/null | grep -q "Partition Table: gpt"; then
            sudo sgdisk -e "$disk" >/dev/null 2>&1
        fi
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
    echo -e "${CYAN}${BOLD}====================================================${RESET}"
    echo -e "${CYAN}${BOLD}   LINUX UNIVERSAL DISK EXPANDER v3.0.4             ${RESET}"
    echo -e "${CYAN}${BOLD}   Multi-Cloud & Virtual Environment Tool           ${RESET}"
    echo -e "${CYAN}${BOLD}====================================================${RESET}"
    echo -e "   Criado por: Benicio Neto | Versão: ${GREEN}3.0.4${RESET}"
    echo -e "${CYAN}${BOLD}====================================================${RESET}"
    echo
}

pause_nav() {
    echo
    echo -e "${YELLOW}${BOLD}[ENTER]${RESET} continuar | ${YELLOW}${BOLD}[V]${RESET} voltar | ${YELLOW}${BOLD}[Q]${RESET} sair"
    read -p "Opção: " resp
    case ${resp,,} in
        'q') exit 0 ;;
        'v') return 1 ;;
        *) return 0 ;;
    esac
}

progress() {
    local steps=$1 msg=$2
    echo -e "  ${BLUE}»${RESET} $msg"
    log_message "EXEC" "$msg"
    for ((i=1; i<=steps; i++)); do
        printf "    [ "
        for ((j=0; j<i; j++)); do printf "■"; done
        for ((j=i; j<steps; j++)); do printf " "; done
        printf " ] %3d%%" $((i*100/steps))
        sleep 0.1
        printf "\r"
    done
    echo -e "\n  ${GREEN}${ICON_SUCCESS}${RESET} $msg concluído."
}

# Início do Script
log_message "START" "Script Universal v3.0.2 iniciado."
check_dependencies

while true; do
    header
    echo -e "${BOLD}${ICON_DISK} PASSO 1: Seleção de Disco Físico${RESET}"
    echo -e "----------------------------------------------------"
    
    DISK_LIST=()
    while read -r line; do
        [[ -n "$line" ]] && DISK_LIST+=("$line")
    done < <(lsblk -d -n -o NAME,SIZE,MODEL,TYPE | grep -i "disk" | awk '{$NF=""; print $0}' | xargs -I{} echo {})
    
    if [ ${#DISK_LIST[@]} -eq 0 ]; then
        for d in /sys/block/sd* /sys/block/vd* /sys/block/nvme*; do
            if [ -e "$d" ]; then
                d_name=$(basename "$d")
                d_size=$(lsblk -dno SIZE "/dev/$d_name" 2>/dev/null)
                [[ -n "$d_size" ]] && DISK_LIST+=("$d_name $d_size")
            fi
        done
    fi

    for i in "${!DISK_LIST[@]}"; do
        echo -e "  ${CYAN}$((i+1)))${RESET} ${DISK_LIST[$i]}"
    done
    echo -e "  ${CYAN}q)${RESET} Sair do script"
    echo -e "----------------------------------------------------"
    read -p "Escolha o número do disco: " DISK_OPT

    [[ ${DISK_OPT,,} == 'q' ]] && exit 0
    
    if [[ ! "$DISK_OPT" =~ ^[0-9]+$ ]] || [ "$DISK_OPT" -lt 1 ] || [ "$DISK_OPT" -gt "${#DISK_LIST[@]}" ]; then
        echo -e "${RED}${ICON_ERROR} Opção inválida!${RESET}"; sleep 1; continue
    fi

    DISCO=$(echo "${DISK_LIST[$((DISK_OPT-1))]}" | awk '{print $1}')
    
    TAMANHO_INICIAL_DISCO=$(cat "/sys/block/$DISCO/size" 2>/dev/null)
    TAMANHO_INICIAL_DISCO=$((TAMANHO_INICIAL_DISCO * 512))
    TAMANHO_INICIAL_HUMANO=$(lsblk -dno SIZE "/dev/$DISCO" | head -n1 | xargs)
    
    echo -e "\n${GREEN}${ICON_SUCCESS} Selecionado: /dev/$DISCO ($TAMANHO_INICIAL_HUMANO)${RESET}"
    pause_nav || continue

    # PASSO 2: RESCAN
    while true; do
        header
        echo -e "${BOLD}${ICON_INFO} PASSO 2: Rescan de Barramento e Kernel${RESET}"
        echo -e "----------------------------------------------------"
        
        sudo partprobe "/dev/$DISCO" >/dev/null 2>&1
        progress 5 "Atualizando Kernel via sysfs..."
        [ -f "/sys/class/block/$DISCO/device/rescan" ] && echo 1 | sudo tee "/sys/class/block/$DISCO/device/rescan" >/dev/null 2>&1
        
        if [ -d "/sys/class/scsi_host" ]; then
            progress 5 "Rescan de barramento SCSI..."
            for host in /sys/class/scsi_host/host*; do echo "- - -" | sudo tee "$host/scan" >/dev/null 2>&1; done
        fi

        if command -v iscsiadm &>/dev/null; then
            progress 5 "Rescan de sessões iSCSI..."
            sudo iscsiadm -m node -R >/dev/null 2>&1 && sudo iscsiadm -m session -R >/dev/null 2>&1
        fi

        TAMANHO_ATUAL_DISCO=$(cat "/sys/block/$DISCO/size" 2>/dev/null)
        TAMANHO_ATUAL_DISCO=$((TAMANHO_ATUAL_DISCO * 512))
        TAMANHO_ATUAL_HUMANO=$(lsblk -dno SIZE "/dev/$DISCO" | head -n1 | xargs)
        
        ESPACO_OCI=$(get_unallocated_space "$DISCO" "$TAMANHO_INICIAL_DISCO")

        if (( $(echo "$ESPACO_OCI > 0" | bc -l) )); then
            echo -e "\n${GREEN}${BOLD}${ICON_SUCCESS} SUCESSO! Espaço novo detectado.${RESET}"
            echo -e "  Tamanho Atual: ${BOLD}$TAMANHO_ATUAL_HUMANO${RESET}"
            echo -e "  Espaço Livre:  ${GREEN}${BOLD}${ESPACO_OCI} GB${RESET}"
            pause_nav && break || continue 2
        else
            if (( $(echo "$ESPACO_OCI == 0" | bc -l) )); then
                echo -e "\n${RED}${ICON_ERROR} AVISO: Nenhum espaço disponível para expansão.${RESET}"
            else
                echo -e "\n${YELLOW}${ICON_INFO} INFO: O rescan não detectou mudanças recentes.${RESET}"
                echo -e "  No entanto, você ainda possui ${BOLD}${ESPACO_OCI} GB${RESET} disponíveis."
            fi
            echo -e "  Tamanho Atual do Disco: $TAMANHO_ATUAL_HUMANO"
            echo -e "----------------------------------------------------"
            echo -e "  ${CYAN}1)${RESET} Tentar Rescan novamente"
            if (( $(echo "$ESPACO_OCI > 0" | bc -l) )); then
                echo -e "  ${CYAN}2)${RESET} Prosseguir para Expansão"
            else
                echo -e "  ${CYAN}2)${RESET} Forçar verificação (Avançar mesmo assim)"
            fi
            echo -e "  ${CYAN}v)${RESET} Voltar ao Passo 1"
            echo -e "----------------------------------------------------"
            read -p "Opção: " OPT
            case $OPT in
                1) continue ;;
                2) break ;;
                v) continue 2 ;;
                *) continue ;;
            esac
        fi
    done

    # PASSO 3: ESTRUTURA
    header
    echo -e "${BOLD}${ICON_PART} PASSO 3: Detecção de Estrutura e Alvo${RESET}"
    echo -e "----------------------------------------------------"
    lsblk "/dev/$DISCO" -o NAME,FSTYPE,SIZE,MOUNTPOINT,TYPE
    echo -e "----------------------------------------------------"

    HAS_PART=$(lsblk -ln -o TYPE "/dev/$DISCO" | grep -q "part" && echo "yes" || echo "no")
    
    if [[ "$HAS_PART" == "yes" ]]; then
        MODO="PART"
        mapfile -t PART_LIST < <(lsblk -ln -o NAME,SIZE,TYPE "/dev/$DISCO" | grep "part")
        echo -e "${BLUE}Partições encontradas:${RESET}"
        for i in "${!PART_LIST[@]}"; do
            echo -e "  ${CYAN}$((i+1)))${RESET} ${PART_LIST[$i]}"
        done
        read -p "Escolha o número da partição: " PART_OPT
        
        if [[ ! "$PART_OPT" =~ ^[0-9]+$ ]] || [ "$PART_OPT" -lt 1 ] || [ "$PART_OPT" -gt "${#PART_LIST[@]}" ]; then
            echo -e "${RED}${ICON_ERROR} Opção inválida!${RESET}"; sleep 1; continue
        fi
        
        PART_ESCOLHIDA=$(echo "${PART_LIST[$((PART_OPT-1))]}" | awk '{print $1}')
        ALVO_NOME="/dev/$PART_ESCOLHIDA"
        PART_NUM=$(echo "$PART_ESCOLHIDA" | grep -oE "[0-9]+$" | tail -1)
        
        MOUNT=$(grep "^$ALVO_NOME " /proc/mounts | awk '{print $2}' | head -n1)
        TYPE=$(grep "^$ALVO_NOME " /proc/mounts | awk '{print $3}' | head -n1)
        [[ -z "$MOUNT" ]] && MOUNT=$(lsblk -no MOUNTPOINT "$ALVO_NOME" | grep -v "^$" | head -n1 | xargs)
        [[ -z "$TYPE" ]] && TYPE=$(lsblk -no FSTYPE "$ALVO_NOME" | grep -v "^$" | head -n1 | xargs)
        [[ -z "$TYPE" ]] && TYPE=$(sudo blkid -o value -s TYPE "$ALVO_NOME")
        
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
        MOUNT=$(grep "^$ALVO_NOME " /proc/mounts | awk '{print $2}' | head -n1)
        TYPE=$(grep "^$ALVO_NOME " /proc/mounts | awk '{print $3}' | head -n1)
        [[ -z "$MOUNT" ]] && MOUNT=$(lsblk -no MOUNTPOINT "$ALVO_NOME" | grep -v "^$" | head -n1 | xargs)
        [[ -z "$TYPE" ]] && TYPE=$(lsblk -no FSTYPE "$ALVO_NOME" | grep -v "^$" | head -n1 | xargs)
        [[ -z "$TYPE" ]] && TYPE=$(sudo blkid -o value -s TYPE "$ALVO_NOME")
        
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
    
    FINAL_TARGET="${ALVO_LVM:-$ALVO_NOME}"
    
    if [[ -n "$MOUNT" && "$MOUNT" != "" ]]; then
        FS_SIZE_BEFORE=$(df -h "$MOUNT" | tail -n1 | awk '{print $2}')
    else
        FS_SIZE_BEFORE=$(lsblk -dno SIZE "$FINAL_TARGET" | head -n1)
    fi

    # OPÇÕES DE TAMANHO
    while true; do
        echo -e "\n${YELLOW}${BOLD}OPÇÕES DE EXPANSÃO:${RESET}"
        echo -e "  ${CYAN}1)${RESET} Usar todo o espaço disponível (100%)"
        echo -e "  ${CYAN}2)${RESET} Definir um valor específico (ex: 10G, 500M)"
        read -p "Escolha uma opção: " OPT_SIZE
        
        EXP_VALUE=""
        if [[ "$OPT_SIZE" == "2" ]]; then
            read -p "Digite o valor (ex: 10G): " EXP_VALUE
            if [[ ! "$EXP_VALUE" =~ ^[0-9]+[GgMm]$ ]]; then
                echo -e "${RED}${ICON_ERROR} Formato inválido!${RESET}"; continue
            fi
            
            # Validação de Sanidade Bloqueante
            local val_num=$(echo "$EXP_VALUE" | grep -oE "[0-9]+")
            local val_unit=$(echo "$EXP_VALUE" | grep -oE "[GgMm]")
            local val_bytes=0
            [[ ${val_unit,,} == "g" ]] && val_bytes=$((val_num * 1024 * 1024 * 1024))
            [[ ${val_unit,,} == "m" ]] && val_bytes=$((val_num * 1024 * 1024))
            
            local free_bytes_raw=$(echo "$ESPACO_OCI * 1024 * 1024 * 1024" | bc | cut -d. -f1)
            if [ "$val_bytes" -gt "$free_bytes_raw" ]; then
                echo -e "${RED}${ICON_ERROR} ERRO: Você solicitou $EXP_VALUE, mas só existem ${ESPACO_OCI}GB livres!${RESET}"
                continue
            fi
            NOVA_CAPACIDADE_HUMANA="${val_num}${val_unit^^} (Aumento)"
        else
            EXP_VALUE=""
            NOVA_CAPACIDADE_HUMANA="${ESPACO_OCI}GB (Aumento)"
        fi
        break
    done

    # RESUMO ANTES DE EXECUTAR
    header
    echo -e "${MAGENTA}${BOLD}📋 RESUMO DA OPERAÇÃO${RESET}"
    echo -e "----------------------------------------------------"
    echo -e "  Disco Físico:   $DISCO"
    echo -e "  Alvo Final:     $FINAL_TARGET"
    echo -e "  Ponto Montagem: ${CYAN}${MOUNT:-"Não montado"}${RESET}"
    echo -e "  Tipo FS:        ${CYAN}$TYPE${RESET}"
    echo -e "  Tamanho Atual:  ${YELLOW}$FS_SIZE_BEFORE${RESET}"
    echo -e "  Ganho Estimado: ${GREEN}+$NOVA_CAPACIDADE_HUMANA${RESET}"
    echo -e "----------------------------------------------------"
    read -p "Confirmar execução? (s/n): " CONFIRM
    [[ ${CONFIRM,,} != 's' ]] && continue

    # PASSO 4: EXECUÇÃO
    header
    echo -e "${BOLD}${ICON_SUCCESS} PASSO 4: Executando Expansão${RESET}"
    echo -e "----------------------------------------------------"
    
    if [[ "$MODO" == "PART" ]]; then
        progress 10 "Expandindo partição física..."
        if [[ -z "$EXP_VALUE" ]]; then
            sudo growpart "/dev/$DISCO" "$PART_NUM" >/dev/null 2>&1 || sudo parted -s "/dev/$DISCO" resizepart "$PART_NUM" 100% >/dev/null 2>&1
        else
            sudo parted -s "/dev/$DISCO" resizepart "$PART_NUM" "$EXP_VALUE" >/dev/null 2>&1
        fi
        sudo partprobe "/dev/$DISCO" >/dev/null 2>&1
    fi

    if [[ "$HAS_LVM" == "yes" ]]; then
        progress 10 "Redimensionando Physical Volume (PV)..."
        PV_TARGET=$(pvs --noheadings -o pv_name | grep "$DISCO" | head -n1 | xargs)
        [[ -z "$PV_TARGET" ]] && PV_TARGET="$ALVO_NOME"
        sudo pvresize "$PV_TARGET" >/dev/null 2>&1
        
        if [[ -n "$ALVO_LVM" ]]; then
            if [[ -z "$EXP_VALUE" ]]; then
                progress 10 "Expandindo Logical Volume (LV)..."
                sudo lvextend -l +100%FREE "$ALVO_LVM" >/dev/null 2>&1
            else
                progress 10 "Expandindo Logical Volume (LV)..."
                sudo lvextend -L +"$EXP_VALUE" "$ALVO_LVM" >/dev/null 2>&1
            fi
        fi
    fi

    if [[ -n "$MOUNT" && "$MOUNT" != "" ]]; then
        if [[ -n "$TYPE" ]]; then
            progress 10 "Expandindo Sistema de Arquivos ($TYPE)..."
            case "$TYPE" in
                xfs) sudo xfs_growfs "$MOUNT" >/dev/null 2>&1 ;;
                ext*) sudo resize2fs "$FINAL_TARGET" >/dev/null 2>&1 ;;
                btrfs) sudo btrfs filesystem resize max "$MOUNT" >/dev/null 2>&1 ;;
            esac
        fi
    fi

    # RESULTADO FINAL
    header
    if [[ -n "$MOUNT" && "$MOUNT" != "" ]]; then
        FS_SIZE_AFTER=$(df -h "$MOUNT" | tail -n1 | awk '{print $2}')
    else
        FS_SIZE_AFTER=$(lsblk -dno SIZE "$FINAL_TARGET" | head -n1)
    fi

    if [[ "$FS_SIZE_BEFORE" == "$FS_SIZE_AFTER" ]]; then
        echo -e "${YELLOW}${BOLD}${ICON_WARN} STATUS: INALTERADO${RESET}"
        echo -e "  O sistema de arquivos já estava no tamanho máximo ou não havia espaço."
    else
        echo -e "${GREEN}${BOLD}${ICON_SUCCESS} OPERAÇÃO CONCLUÍDA COM SUCESSO!${RESET}"
    fi

    echo -e "----------------------------------------------------"
    if [[ -n "$MOUNT" && "$MOUNT" != "" ]]; then
        df -h "$MOUNT"
    else
        lsblk "$FINAL_TARGET"
    fi
    echo -e "----------------------------------------------------"
    
    pause_nav || continue
    exit 0
done
