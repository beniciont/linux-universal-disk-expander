#!/bin/bash

# ==============================================================================
# LINUX UNIVERSAL DISK EXPANDER - MULTI-CLOUD & VIRTUAL
# Criado por: Benicio Neto
# Versão: 3.1.2
# Última Atualização: 04/01/2026
#
# HISTÓRICO DE VERSÕES:
# 1.0.0 a 2.8.0 - Evolução focada em OCI.
# 2.9.0-beta (03/01/2026) - NEW: Rescan agnóstico (OCI, Azure, AWS, VirtualBox).
# 3.0.9 (05/01/2026) - FIX: Detecção de espaço livre interno no LVM (PFree) e correção de bug na seleção de disco.
# 3.1.0 (04/01/2026) - REMOVE: Opção "Forçar". IMPROVE: Detecção inteligente de LVM e exibição de espaço disponível.
# 3.1.1 (04/01/2026) - FIX: Detecção resiliente de LVM PFree e correção de dependências.
# 3.1.2 (04/01/2026) - IMPROVE: Seleção numérica para partições e volumes LVM.
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
    local deps=("gdisk" "parted" "xfsprogs" "e2fsprogs" "bc" "lvm2")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            log_message "INFO" "Dependência '$dep' não encontrada. Tentando instalar..."
            if command -v yum &>/dev/null; then
                sudo yum install -y "$dep" >/dev/null 2>&1
            elif command -v apt-get &>/dev/null; then
                sudo apt-get update >/dev/null 2>&1
                sudo apt-get install -y "$dep" >/dev/null 2>&1
            fi
            
            if ! command -v "$dep" &>/dev/null; then
                log_message "ERROR" "Falha ao instalar a dependência '$dep'. O script pode não funcionar corretamente."
            else
                log_message "INFO" "Dependência '$dep' instalada com sucesso."
            fi
        fi
    done
}

# Função para obter o espaço não alocado
get_unallocated_space() {
    local disk_name=$1
    local disk="/dev/$disk_name"
    
    if command -v sgdisk &>/dev/null; then
        sudo sgdisk -e "$disk" >/dev/null 2>&1
    fi

    local disk_size_bytes=$(cat "/sys/block/$disk_name/size" 2>/dev/null)
    disk_size_bytes=$((disk_size_bytes * 512))
    
    local used_bytes=0
    local lvm_free_bytes=0
    
    local has_parts=$(lsblk -ln -o TYPE "$disk" | grep -q "part" && echo "yes" || echo "no")
    if [[ "$has_parts" == "yes" ]]; then
        local last_part_end_sector=$(sudo parted -s "$disk" unit s print | grep -E "^ [0-9]+" | tail -n1 | awk '{print $3}' | tr -d 's')
        [[ -z "$last_part_end_sector" ]] && last_part_end_sector=0
        used_bytes=$((last_part_end_sector * 512))
    else
        if lsblk -no FSTYPE "$disk" | grep -q "."; then
            used_bytes=$disk_size_bytes
        else
            used_bytes=0
        fi
    fi

    local pvs_found=$(lsblk -ln -o NAME,FSTYPE "$disk" | grep "LVM" | awk '{print $1}')
    for pv in $pvs_found; do
        local pv_path=$pv
        [[ ! "$pv_path" =~ ^/ ]] && pv_path="/dev/$pv"
        if command -v pvs &>/dev/null; then
            local pv_free=$(sudo pvs --noheadings --units b --options pv_free "$pv_path" 2>/dev/null | grep -oE "[0-9]+")
            if [[ -n "$pv_free" ]]; then
                lvm_free_bytes=$((lvm_free_bytes + pv_free))
            fi
        fi
    done

    local physical_free_bytes=$((disk_size_bytes - used_bytes))
    [[ "$physical_free_bytes" -lt 0 ]] && physical_free_bytes=0
    local total_free_bytes=$((physical_free_bytes + lvm_free_bytes))
    
    log_message "DEBUG" "get_unallocated_space($disk): Total=$disk_size_bytes, Usado=$used_bytes, PFree_LVM=$lvm_free_bytes, Livre_Fisico=$physical_free_bytes, Livre_Total=$total_free_bytes"

    if [[ "$total_free_bytes" -lt 10485760 ]]; then # Menos de 10MB
        echo "0"
    else
        echo "scale=2; $total_free_bytes / 1024 / 1024 / 1024" | bc
    fi
}

header() {
    clear
    echo "===================================================="    echo "   LINUX UNIVERSAL DISK EXPANDER v3.2.4-beta 🧪"
    echo "   Multi-Cloud & Virtual Environment Tool"
    echo "===================================================="
    echo "   Criado por: Benicio Neto | Versão: 3.2.4-beta"
    echo "===================================================="
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
    echo "  » $msg"
    log_message "EXEC" "$msg"
    printf "    [ "
    for ((i=1; i<=steps; i++)); do
        printf "■"
        sleep 0.1
    done
    printf " ] 100%%\n"
    echo "  ${GREEN}✅ $msg... concluído.${RESET}"
}

log_message "START" "Script Universal v3.1.2 iniciado."
check_dependencies

while true; do
    header
    
    DISCOS=()
    mapfile -t DISCOS < <(lsblk -d -n -o NAME,TYPE | grep "disk" | awk '{print $1}')

    echo "${YELLOW}📦 PASSO 1: Seleção de Disco Físico${RESET}"
    echo "----------------------------------------------------"
    lsblk -d -n -o NAME,SIZE,TYPE,MODEL | grep "disk" | awk '{print "  " NR ") " $1 " " $2 " " $4}'
    echo "  q) Sair do script"
    echo "----------------------------------------------------"
    echo -n "${BLUE}Escolha o número do disco ou digite o nome: ${RESET}"
    read ESCOLHA
    
    [[ ${ESCOLHA,,} == 'q' ]] && exit 0
    
    if [[ "$ESCOLHA" =~ ^[0-9]+$ ]]; then
        INDEX=$((ESCOLHA - 1))
        DISCO=${DISCOS[$INDEX]}
    else
        DISCO=$ESCOLHA
    fi
    
    DISCO=$(echo "$DISCO" | xargs)
    if [[ -z "$DISCO" || ! -b "/dev/$DISCO" ]]; then
        echo "${RED}ERRO: Disco /dev/$DISCO não encontrado!${RESET}"; sleep 2; continue
    fi

    TAMANHO_INICIAL_HUMANO=$(lsblk -dno SIZE "/dev/$DISCO" | head -n1 | xargs)
    echo -e "\n${GREEN}🎯 DISCO SELECIONADO: /dev/$DISCO ($TAMANHO_INICIAL_HUMANO)${RESET}"
    pause_nav || continue

    while true; do
        header
        echo "${YELLOW}ℹ️ PASSO 2: Rescan de Barramento e Kernel${RESET}"
        echo "----------------------------------------------------"
        
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

        sudo partprobe "/dev/$DISCO" >/dev/null 2>&1
        
        TAMANHO_ATUAL_HUMANO=$(lsblk -dno SIZE "/dev/$DISCO" | head -n1 | xargs)
        ESPACO_LIVRE=$(get_unallocated_space "$DISCO")

        if (( $(echo "$ESPACO_LIVRE > 0" | bc -l) )); then
            echo -e "\n${GREEN}${BOLD}✅ SUCESSO! Espaço disponível detectado.${RESET}"
            echo "  Tamanho Atual do Disco: $TAMANHO_ATUAL_HUMANO"
            echo "  Espaço Total para Expansão: ${ESPACO_LIVRE} GB"
            echo "  (Inclui espaço físico não alocado e espaço livre em LVM)"
            pause_nav && break || continue 2
        else
            echo -e "\n${RED}❌ AVISO: Nenhum espaço disponível para expansão.${RESET}"
            echo "  Tamanho Atual do Disco: $TAMANHO_ATUAL_HUMANO"
            echo "----------------------------------------------------"
            echo "  1) Tentar Rescan novamente"
            echo "  v) Voltar ao Passo 1"
            echo "----------------------------------------------------"
            echo -n "Opção: "
            read OPT
            case $OPT in
                1) continue ;;
                v) continue 2 ;;
                *) continue ;;
            esac
        fi
    done

    header
    echo "${CYAN}🔍 PASSO 3: Estrutura Detectada${RESET}"
    echo "----------------------------------------------------"
    lsblk "/dev/$DISCO" -o NAME,FSTYPE,SIZE,MOUNTPOINT,TYPE
    echo "----------------------------------------------------"

    HAS_PART=$(lsblk -ln -o TYPE "/dev/$DISCO" | grep -q "part" && echo "yes" || echo "no")
    
    if [[ "$HAS_PART" == "yes" ]]; then
        MODO="PART"
        echo -e "\n${BLUE}Selecione a partição alvo:${RESET}"
        PARTS=()
        mapfile -t PARTS < <(lsblk -ln -o NAME,TYPE "/dev/$DISCO" | grep "part" | awk '{print $1}')
        for i in "${!PARTS[@]}"; do
            echo "  $((i+1))) /dev/${PARTS[$i]}"
        done
        echo -n "Escolha o número: "
        read P_IDX
        PART_ESCOLHIDA=${PARTS[$((P_IDX-1))]}
        
        if [[ -z "$PART_ESCOLHIDA" || ! -b "/dev/$PART_ESCOLHIDA" ]]; then
            echo "${RED}ERRO: Partição inválida!${RESET}"; sleep 2; continue
        fi
        
        ALVO_NOME="/dev/$PART_ESCOLHIDA"
        PART_NUM=$(echo "$PART_ESCOLHIDA" | grep -oE "[0-9]+$" | tail -1)
        MOUNT=$(lsblk -no MOUNTPOINT "$ALVO_NOME" | head -n1)
        TYPE=$(lsblk -no FSTYPE "$ALVO_NOME" | head -n1)
        
        if lsblk -no FSTYPE "$ALVO_NOME" | grep -qi "LVM"; then
            HAS_LVM="yes"
            echo -e "\n${YELLOW}Selecione o Logical Volume (LV) para expandir:${RESET}"
            LVS=()
            mapfile -t LVS < <(lsblk -ln -o NAME,TYPE "$ALVO_NOME" | grep "lvm" | awk '{print $1}')
            for i in "${!LVS[@]}"; do
                LV_SIZE=$(lsblk -no SIZE "/dev/mapper/${LVS[$i]}" 2>/dev/null || lsblk -no SIZE "/dev/${LVS[$i]}")
                echo "  $((i+1))) ${LVS[$i]} ($LV_SIZE)"
            done
            echo -n "Escolha o número (ou ENTER para pular): "
            read L_IDX
            if [[ -n "$L_IDX" ]]; then
                LV_ESCOLHIDO=${LVS[$((L_IDX-1))]}
                [[ -n "$LV_ESCOLHIDO" ]] && ALVO_LVM="/dev/mapper/$LV_ESCOLHIDO" || ALVO_LVM=""
            fi
            
            if [[ -n "$ALVO_LVM" ]]; then
                MOUNT=$(lsblk -no MOUNTPOINT "$ALVO_LVM" | head -n1)
                TYPE=$(lsblk -no FSTYPE "$ALVO_LVM" | head -n1)
            fi
        else
            HAS_LVM="no"
            ALVO_LVM=""
        fi
    else
        MODO="RAW"
        ALVO_NOME="/dev/$DISCO"
        MOUNT=$(lsblk -no MOUNTPOINT "$ALVO_NOME" | head -n1)
        TYPE=$(lsblk -no FSTYPE "$ALVO_NOME" | head -n1)
        
        if lsblk -no FSTYPE "$ALVO_NOME" | grep -qi "LVM"; then
            HAS_LVM="yes"
            echo -e "\n${YELLOW}Selecione o Logical Volume (LV) para expandir:${RESET}"
            LVS=()
            mapfile -t LVS < <(lsblk -ln -o NAME,TYPE "$ALVO_NOME" | grep "lvm" | awk '{print $1}')
            for i in "${!LVS[@]}"; do
                LV_SIZE=$(lsblk -no SIZE "/dev/mapper/${LVS[$i]}" 2>/dev/null || lsblk -no SIZE "/dev/${LVS[$i]}")
                echo "  $((i+1))) ${LVS[$i]} ($LV_SIZE)"
            done
            echo -n "Escolha o número (ou ENTER para pular): "
            read L_IDX
            if [[ -n "$L_IDX" ]]; then
                LV_ESCOLHIDO=${LVS[$((L_IDX-1))]}
                [[ -n "$LV_ESCOLHIDO" ]] && ALVO_LVM="/dev/mapper/$LV_ESCOLHIDO" || ALVO_LVM=""
            fi
            
            if [[ -n "$ALVO_LVM" ]]; then
                MOUNT=$(lsblk -no MOUNTPOINT "$ALVO_LVM" | head -n1)
                TYPE=$(lsblk -no FSTYPE "$ALVO_LVM" | head -n1)
            fi
        else
            HAS_LVM="no"
            ALVO_LVM=""
        fi
    fi

    FINAL_TARGET="${ALVO_LVM:-$ALVO_NOME}"
    if [[ -n "$MOUNT" ]]; then
        FS_SIZE_BEFORE=$(df -B1 "$MOUNT" | tail -n1 | awk '{print $2}')
    else
        FS_SIZE_BEFORE=$(lsblk -bdno SIZE "$FINAL_TARGET" | head -n1)
    fi

    echo -e "\n${YELLOW}⚙️ OPÇÕES DE EXPANSÃO:${RESET}"
    echo "  1) Usar todo o espaço disponível (100%)"
    echo "  2) Definir um valor específico (ex: 10G, 500M)"
    echo -n "Escolha uma opção: "
    read OPT_SIZE
    
    EXP_VALUE=""
    if [[ "$OPT_SIZE" == "2" ]]; then
        echo -n "Digite o valor (ex: 10G, 500M): "
        read EXP_VALUE
        if [[ ! "$EXP_VALUE" =~ ^[0-9]+[GgMm]$ ]]; then
            echo "${RED}ERRO: Formato inválido!${RESET}"; sleep 2; continue
        fi
    fi

    echo -e "\n${BLUE}⚠️ Confirmar expansão de $FINAL_TARGET? (s/n)${RESET}"
    read CONFIRM
    [[ ${CONFIRM,,} != 's' ]] && continue

    header
    echo "${GREEN}🚀 PASSO 4: Executando Expansão${RESET}"
    echo "----------------------------------------------------"
    
    if [[ "$MODO" == "PART" ]]; then
        DISK_SIZE_BYTES=$(cat "/sys/block/$DISCO/size" 2>/dev/null)
        DISK_SIZE_BYTES=$((DISK_SIZE_BYTES * 512))
        LAST_PART_END_SECTOR=$(sudo parted -s "/dev/$DISCO" unit s print | grep -E "^ [0-9]+" | tail -n1 | awk '{print $3}' | tr -d 's')
        [[ -z "$LAST_PART_END_SECTOR" ]] && LAST_PART_END_SECTOR=0
        USED_BYTES=$((LAST_PART_END_SECTOR * 512))
        
        if [[ "$DISK_SIZE_BYTES" -gt "$USED_BYTES" ]]; then
            progress 5 "Redimensionando partição física..."
            if [[ -z "$EXP_VALUE" ]]; then
                sudo growpart "/dev/$DISCO" "$PART_NUM" >/dev/null 2>&1 || sudo parted -s "/dev/$DISCO" resizepart "$PART_NUM" 100% >/dev/null 2>&1
            else
                sudo parted -s "/dev/$DISCO" resizepart "$PART_NUM" "$EXP_VALUE" >/dev/null 2>&1
            fi
            sudo partprobe "/dev/$DISCO" >/dev/null 2>&1
        fi
    fi

    if [[ "$HAS_LVM" == "yes" ]]; then
        progress 5 "Atualizando LVM (PV e LV)..."
        PV_TARGET=$(pvs --noheadings -o pv_name | grep "$DISCO" | head -n1 | xargs)
        [[ -z "$PV_TARGET" ]] && PV_TARGET="$ALVO_NOME"
        sudo pvresize "$PV_TARGET" >/dev/null 2>&1
        
        if [[ -n "$ALVO_LVM" ]]; then
            if [[ -z "$EXP_VALUE" ]]; then
                sudo lvextend -l +100%FREE "$ALVO_LVM" >/dev/null 2>&1
            else
                sudo lvextend -L +"$EXP_VALUE" "$ALVO_LVM" >/dev/null 2>&1
            fi
        fi
    fi

    if [[ -n "$MOUNT" ]]; then
        progress 5 "Expandindo Sistema de Arquivos ($TYPE)..."
        case "$TYPE" in
            xfs) sudo xfs_growfs "$MOUNT" >/dev/null 2>&1 ;;
            ext*) sudo resize2fs "$FINAL_TARGET" >/dev/null 2>&1 ;;
            btrfs) sudo btrfs filesystem resize max "$MOUNT" >/dev/null 2>&1 ;;
        esac
    fi

    if [[ -n "$MOUNT" ]]; then
        FS_SIZE_AFTER=$(df -B1 "$MOUNT" | tail -n1 | awk '{print $2}')
    else
        FS_SIZE_AFTER=$(lsblk -bdno SIZE "$FINAL_TARGET" | head -n1)
    fi

    header
    echo "${GREEN}🏁 RESULTADO FINAL${RESET}"
    echo "----------------------------------------------------"
    if [[ -n "$MOUNT" ]]; then
        df -h "$MOUNT"
    else
        lsblk "$FINAL_TARGET"
    fi
    
    echo -e "\n----------------------------------------------------"
    if [[ "$FS_SIZE_AFTER" -gt "$FS_SIZE_BEFORE" ]]; then
        echo -e "STATUS: ${GREEN}${BOLD}✅ SUCESSO! Expansão concluída.${RESET}"
    else
        echo -e "STATUS: ${YELLOW}${BOLD}⚠️ INALTERADO: O tamanho não mudou.${RESET}"
    fi
    echo "----------------------------------------------------"
    
    pause_nav || continue
    exit 0
done
