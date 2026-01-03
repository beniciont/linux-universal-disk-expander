#!/bin/bash

# ==============================================================================
# EXPANSAO OCI LINUX - FERRAMENTA UNIVERSAL
# Criado por: Benicio Neto
# Versão: 2.7.3 (PRODUÇÃO)
# Última Atualização: 03/01/2026
#
# HISTÓRICO DE VERSÕES:
# 1.0.0 a 2.7.2 - Evolução e correções de bugs.
# 2.7.3 (03/01/2026) - FIX: Nova lógica infalível de detecção de espaço livre (OCI).
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

# Função para obter o espaço não alocado (Espaço OCI)
get_unallocated_space() {
    local disk="/dev/$1"
    
    # Tenta corrigir a tabela de partições GPT se houver espaço no final
    if command -v sgdisk &>/dev/null; then
        sudo sgdisk -e "$disk" >/dev/null 2>&1
    fi

    local disk_size_bytes=$(lsblk -bdno SIZE "$disk" | head -n1 | tr -d ' ')
    local used_bytes=0
    
    # 1. Verifica se há partições
    local has_parts=$(lsblk -ln -o TYPE "$disk" | grep -q "part" && echo "yes" || echo "no")
    
    if [[ "$has_parts" == "yes" ]]; then
        # Se tem partição, o espaço usado é o fim da última partição
        used_bytes=$(sudo parted -s "$disk" unit B print | grep -E "^ [0-9]+" | tail -n1 | awk '{print $3}' | tr -d 'B')
    else
        # 2. Se não tem partição, verifica se é um PV LVM
        local pv_size=$(sudo pvs --noheadings --units b --options pv_size "$disk" 2>/dev/null | grep -oE "[0-9]+" | head -n1)
        if [[ -n "$pv_size" ]]; then
            used_bytes=$pv_size
        else
            # 3. Se não é LVM, verifica se tem um Sistema de Arquivos direto
            local has_fs=$(lsblk -no FSTYPE "$disk" | head -n1)
            if [[ -n "$has_fs" ]]; then
                # Se tem FS direto, assumimos que ele ocupa o que o kernel vê no momento
                used_bytes=$disk_size_bytes
            else
                # Disco vazio
                used_bytes=0
            fi
        fi
    fi

    local free_bytes=$((disk_size_bytes - used_bytes))
    
    # Log de depuração
    log_message "DEBUG" "get_unallocated_space($disk): Total=$disk_size_bytes, Usado=$used_bytes, Livre=$free_bytes"

    if [[ "$free_bytes" -lt 1048576 ]]; then
        echo "0"
    else
        echo "scale=2; $free_bytes / 1024 / 1024 / 1024" | bc
    fi
}

header() {
    clear
    echo "=================================="
    echo " EXPANSAO OCI LINUX v2.7.3 "
    echo " Criado por: Benicio Neto"
    echo " Versão: 2.7.3 (PRODUÇÃO)"
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
        sleep 0.1
        printf "\r               \r"
    done
    echo "  ${GREEN}[OK]${RESET} $msg"
}

# Início do Script
log_message "START" "Script Universal v2.7.3 iniciado."
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

    # Captura o tamanho inicial absoluto para evitar falsos positivos
    TAMANHO_INICIAL_DISCO=$(lsblk -bdno SIZE "/dev/$DISCO" | head -n1 | tr -d ' ')
    TAMANHO_INICIAL_HUMANO=$(lsblk -dno SIZE "/dev/$DISCO" | head -n1)
    
    echo -e "\n${GREEN}DISCO SELECIONADO: /dev/$DISCO ($TAMANHO_INICIAL_HUMANO)${RESET}"
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
        
        TAMANHO_ATUAL_DISCO=$(lsblk -bdno SIZE "/dev/$DISCO" | head -n1 | tr -d ' ')
        TAMANHO_ATUAL_HUMANO=$(lsblk -dno SIZE "/dev/$DISCO" | head -n1)
        
        ESPACO_OCI=$(get_unallocated_space "$DISCO")

        # Lógica de Sucesso: O disco cresceu OU há espaço não alocado real
        if [ "$TAMANHO_ATUAL_DISCO" -gt "$TAMANHO_INICIAL_DISCO" ] || (( $(echo "$ESPACO_OCI > 0" | bc -l) )); then
            GANHO_BYTES=$((TAMANHO_ATUAL_DISCO - TAMANHO_INICIAL_DISCO))
            GANHO_GB=$(echo "scale=2; $GANHO_BYTES / 1024 / 1024 / 1024" | bc)
            
            echo -e "\n${GREEN}${BOLD}SUCESSO! Espaço novo detectado.${RESET}"
            echo "Tamanho Atual: $TAMANHO_ATUAL_HUMANO (+$GANHO_GB GB detectados)"
            echo "Espaço não alocado (OCI): ${ESPACO_OCI} GB"
            pause_nav && break || continue 2
        else
            echo -e "\n${RED}AVISO: Nenhum espaço novo detectado ($TAMANHO_ATUAL_HUMANO).${RESET}"
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
    HAS_LVM=$(lsblk -ln -o FSTYPE "/dev/$DISCO" | grep -qi "LVM" && echo "yes" || echo "no")
    
    if [[ "$HAS_LVM" == "yes" ]]; then
        MODO="LVM"
        ALVO_NOME=$(lsblk -ln -o NAME,MOUNTPOINT "/dev/$DISCO" | grep "lvm" | sort -k2 -r | head -n1 | awk '{print "/dev/mapper/"$1}')
        MOUNT=$(lsblk -no MOUNTPOINT "$ALVO_NOME" | head -n1)
        TYPE=$(lsblk -no FSTYPE "$ALVO_NOME" | head -n1)
    elif [[ "$HAS_PART" == "yes" ]]; then
        MODO="PART"
        PART_NOME=$(lsblk -ln -o NAME,MOUNTPOINT "/dev/$DISCO" | grep "part" | sort -k2 -r | head -n1 | awk '{print $1}')
        ALVO_NOME="/dev/$PART_NOME"
        PART_NUM=$(echo "$PART_NOME" | grep -oE "[0-9]+$" | tail -1)
        MOUNT=$(lsblk -no MOUNTPOINT "$ALVO_NOME" | head -n1)
        TYPE=$(lsblk -no FSTYPE "$ALVO_NOME" | head -n1)
    else
        MODO="RAW"
        ALVO_NOME="/dev/$DISCO"
        MOUNT=$(lsblk -no MOUNTPOINT "$ALVO_NOME" | head -n1)
        TYPE=$(lsblk -no FSTYPE "$ALVO_NOME" | head -n1)
    fi

    if [[ -n "$MOUNT" ]]; then
        FS_SIZE_BEFORE=$(df -B1 "$MOUNT" | tail -n1 | awk '{print $2}')
    else
        FS_SIZE_BEFORE=$(lsblk -bdno SIZE "$ALVO_NOME" | head -n1)
    fi

    echo -e "\n${BLUE}Deseja expandir $ALVO_NOME usando todo o espaço disponível? (s/n)${RESET}"
    read CONFIRM
    [[ ${CONFIRM,,} != 's' ]] && continue

    # PASSO 4: EXECUÇÃO
    header
    echo "${GREEN}PASSO 4: Executando Expansão Universal${RESET}"
    echo "================================"
    
    if [[ "$MODO" == "PART" ]]; then
        progress 2 "Expandindo partição $PART_NUM..."
        sudo growpart "/dev/$DISCO" "$PART_NUM" >/dev/null 2>&1 || sudo parted -s "/dev/$DISCO" resizepart "$PART_NUM" 100% >/dev/null 2>&1
        sudo partprobe "/dev/$DISCO" >/dev/null 2>&1
    fi

    if [[ "$HAS_LVM" == "yes" ]]; then
        progress 2 "Redimensionando Physical Volume (PV)..."
        PV_TARGET=$(pvs --noheadings -o pv_name | grep "$DISCO" | head -n1 | xargs)
        sudo pvresize "$PV_TARGET" >/dev/null 2>&1
        progress 2 "Expandindo Logical Volume (LV)..."
        sudo lvextend -l +100%FREE "$ALVO_NOME" >/dev/null 2>&1
    fi

    if [[ -n "$MOUNT" ]]; then
        progress 2 "Expandindo Sistema de Arquivos ($TYPE)..."
        case "$TYPE" in
            xfs) sudo xfs_growfs "$MOUNT" >/dev/null 2>&1 ;;
            ext*) sudo resize2fs "$ALVO_NOME" >/dev/null 2>&1 ;;
            btrfs) sudo btrfs filesystem resize max "$MOUNT" >/dev/null 2>&1 ;;
        esac
    fi

    if [[ -n "$MOUNT" ]]; then
        FS_SIZE_AFTER=$(df -B1 "$MOUNT" | tail -n1 | awk '{print $2}')
    else
        FS_SIZE_AFTER=$(lsblk -bdno SIZE "$ALVO_NOME" | head -n1)
    fi

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
