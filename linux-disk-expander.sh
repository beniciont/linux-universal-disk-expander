#!/bin/bash

# ==============================================================================
# EXPANSOR DE DISCO UNIVERSAL LINUX - MULTI-NUVEM & VIRTUAL
# Criado por: Benicio Neto
# Versão: 3.2.8-beta (DESENVOLVIMENTO)
# Última Atualização: 08/01/2026 (Fix: Syntax & EXT4 Online Shrink Error)
# ==============================================================================

# Configurações de Log
LOG_FILE="/var/log/linux-disk-expander-develop.log"
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
        sudo chmod 666 "$LOG_FILE" 2>/dev/null
    fi

    echo "[$timestamp] [$level] [User: $USER_EXEC] - $message" | sudo tee -a "$LOG_FILE" >/dev/null 2>&1
}

# Função para instalar dependências
check_dependencies() {
    local deps=("parted" "xfsprogs" "e2fsprogs" "bc" "lvm2")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            log_message "INFO" "Dependência '$dep' não encontrada. Tentando instalar..."
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
    
    sudo parted -s "$disk" print >/dev/null 2>&1

    local disk_size_bytes=$(cat "/sys/block/$disk_name/size" 2>/dev/null)
    disk_size_bytes=$((disk_size_bytes * 512))
    
    local used_bytes=0
    local lvm_free_bytes=0
    local source="DISK_GROWTH"
    local mount_point=""
    
    local has_parts=$(lsblk -ln -o TYPE "$disk" | grep -q "part" && echo "yes" || echo "no")
    if [[ "$has_parts" == "yes" ]]; then
        local last_part_end_sector=$(sudo parted -s "$disk" unit s print | grep -E "^ [0-9]+" | tail -n1 | awk '{print $3}' | tr -d 's')
        [[ -z "$last_part_end_sector" ]] && last_part_end_sector=0
        used_bytes=$((last_part_end_sector * 512))
    else
        local fstype=$(lsblk -no FSTYPE "$disk" | head -n1 | xargs)
        mount_point=$(lsblk -no MOUNTPOINT "$disk" | head -n1 | xargs)
        
        if [[ -n "$fstype" ]]; then
            if [[ "$fstype" == "LVM2_member" ]]; then
                if command -v pvs &>/dev/null; then
                    local pv_size=$(sudo pvs --noheadings --units b --options pv_size "$disk" 2>/dev/null | grep -oE "[0-9]+")
                    local pv_free=$(sudo pvs --noheadings --units b --options pv_free "$disk" 2>/dev/null | grep -oE "[0-9]+")
                    [[ -n "$pv_size" && -n "$pv_free" ]] && used_bytes=$((pv_size - pv_free))
                fi
            elif [[ -n "$mount_point" ]]; then
                local df_size=$(df -B1 --output=size "$mount_point" | tail -n1 | xargs)
                [[ -n "$df_size" ]] && used_bytes=$df_size
            else
                used_bytes=$(sudo blockdev --getsize64 "$disk" 2>/dev/null)
            fi
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
    
    local total_free_bytes=0
    if [[ "$lvm_free_bytes" -gt "$physical_free_bytes" ]]; then
        total_free_bytes=$lvm_free_bytes
        source="LVM_FREE"
    else
        total_free_bytes=$physical_free_bytes
        source="DISK_GROWTH"
    fi
    
    local total_gb=$(echo "scale=2; $disk_size_bytes / 1024 / 1024 / 1024" | bc)
    local used_gb=$(echo "scale=2; $used_bytes / 1024 / 1024 / 1024" | bc)
    local free_gb=$(echo "scale=2; $total_free_bytes / 1024 / 1024 / 1024" | bc)

    echo "$total_gb:$used_gb:$free_gb:$source:$mount_point"
}

header() {
    clear
    echo "===================================================="
    echo "   EXPANSOR DE DISCO UNIVERSAL LINUX v3.2.8-beta 🧪"
    echo "   Ferramenta para Ambientes Multi-Nuvem e Virtuais"
    echo "===================================================="
    echo "   Criado por: Benicio Neto | Versão: 3.2.8-beta"
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

log_message "START" "Script Universal v3.2.6-beta iniciado."
check_dependencies

while true; do
    header
    DISCOS=()
    mapfile -t DISCOS < <(lsblk -d -n -o NAME,TYPE | grep "disk" | awk '{print $1}')

    echo "${YELLOW}📦 PASSO 1: Seleção de Disco (Block Device)${RESET}"
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
        
        progress 5 "Rescan de barramento SCSI (Agressivo)..."
        if [ -d "/sys/class/scsi_host" ]; then
            for host in /sys/class/scsi_host/host*; do echo "- - -" | sudo tee "$host/scan" >/dev/null 2>&1; done
        fi
        if [ -d "/sys/class/scsi_device" ]; then
            for dev in /sys/class/scsi_device/*; do echo 1 | sudo tee "$dev/device/rescan" >/dev/null 2>&1; done
        fi

        if command -v iscsiadm &>/dev/null; then
            progress 5 "Rescan de sessões iSCSI..."
            sudo iscsiadm -m node -R >/dev/null 2>&1 && sudo iscsiadm -m session -R >/dev/null 2>&1
        fi

        sudo blockdev --rereadpt "/dev/$DISCO" >/dev/null 2>&1
        sudo partprobe "/dev/$DISCO" >/dev/null 2>&1
        sudo udevadm settle
        
        RESULTADO_ESPACO=$(get_unallocated_space "$DISCO")
        TOTAL_GB=$(echo "$RESULTADO_ESPACO" | cut -d':' -f1)
        USADO_GB=$(echo "$RESULTADO_ESPACO" | cut -d':' -f2)
        LIVRE_GB=$(echo "$RESULTADO_ESPACO" | cut -d':' -f3)
        FONTE_ESPACO=$(echo "$RESULTADO_ESPACO" | cut -d':' -f4)
        PONTO_MONTAGEM=$(echo "$RESULTADO_ESPACO" | cut -d':' -f5)

        echo -e "\n${CYAN}📊 Resumo de Espaço em /dev/$DISCO:${RESET}"
        echo "  Tamanho Total (Kernel): ${TOTAL_GB} GB"
        echo "  Tamanho Atual do FS:    ${USADO_GB} GB"
        echo "  Espaço Livre p/ Ganhar: ${LIVRE_GB} GB"
        [[ -n "$PONTO_MONTAGEM" ]] && echo "  Montado em:             ${GREEN}$PONTO_MONTAGEM${RESET}"
        
        if (( $(echo "$LIVRE_GB > 0.1" | bc -l) )); then
            case "$FONTE_ESPACO" in
                "LVM_FREE") FONTE_DISPLAY="Espaço Livre no LVM (PFree)" ;;
                "DISK_GROWTH") FONTE_DISPLAY="Crescimento do Disco Físico" ;;
                *) FONTE_DISPLAY="Espaço Não Alocado" ;;
            esac
            echo -e "\n${GREEN}${BOLD}✅ SUCESSO! Espaço disponível para expansão.${RESET}"
            echo "  Fonte Detectada: $FONTE_DISPLAY"
            pause_nav && break || continue 2
        else
            echo -e "\n${RED}❌ AVISO: Nenhum espaço novo detectado após o Rescan.${RESET}"
            echo "----------------------------------------------------"
            echo "  1) Tentar Rescan novamente"
            echo "  v) Voltar ao Passo 1"
            echo "----------------------------------------------------"
            echo -n "Opção: "
            read OPT
            case ${OPT,,} in
                1) continue ;;
                v) continue 2 ;;
                *) continue ;;
            esac
        fi
    done

    while true; do
        HAS_PART=$(lsblk -ln -o TYPE "/dev/$DISCO" | grep -q "part" && echo "yes" || echo "no")
        ALVO_LVM=""
        if [[ "$HAS_PART" == "yes" ]]; then
            header
            echo "${CYAN}🔍 PASSO 3: Estrutura Detectada${RESET}"
            echo "----------------------------------------------------"
            lsblk "/dev/$DISCO" -o NAME,FSTYPE,SIZE,MOUNTPOINT,TYPE
            echo "----------------------------------------------------"
            MODO="PART"
            echo -e "\n${BLUE}Selecione a partição alvo:${RESET}"
            PARTS=(); mapfile -t PARTS < <(lsblk -ln -o NAME,TYPE "/dev/$DISCO" | grep "part" | awk '{print $1}')
            for i in "${!PARTS[@]}"; do echo "  $((i+1))) /dev/${PARTS[$i]}"; done
            echo "  v) Voltar ao Passo 2"
            echo "----------------------------------------------------"
            echo -n "Escolha o número: "; read P_IDX
            [[ ${P_IDX,,} == 'v' ]] && break
            
            PART_ESCOLHIDA=${PARTS[$((P_IDX-1))]}
            [[ -z "$PART_ESCOLHIDA" || ! -b "/dev/$PART_ESCOLHIDA" ]] && { echo "${RED}ERRO: Partição inválida!${RESET}"; sleep 2; continue; }
            
            ALVO_NOME="/dev/$PART_ESCOLHIDA"
            PART_NUM=$(echo "$PART_ESCOLHIDA" | grep -oE "[0-9]+$" | tail -1)
            
            if lsblk -no FSTYPE "$ALVO_NOME" | grep -qi "LVM"; then
                HAS_LVM="yes"
                while true; do
                    header
                    echo "${YELLOW}Selecione o Logical Volume (LV) para expandir:${RESET}"
                    LVS=(); mapfile -t LVS < <(lsblk -ln -o NAME,TYPE "$ALVO_NOME" | grep "lvm" | awk '{print $1}')
                    for i in "${!LVS[@]}"; do
                        LV_SIZE=$(lsblk -no SIZE "/dev/mapper/${LVS[$i]}" 2>/dev/null || lsblk -no SIZE "/dev/${LVS[$i]}")
                        echo "  $((i+1))) ${LVS[$i]} ($LV_SIZE)"
                    done
                    echo "  v) Voltar à seleção de partição"
                    echo "----------------------------------------------------"
                    echo -n "Escolha o número (ou ENTER para pular): "; read L_IDX
                    [[ ${L_IDX,,} == 'v' ]] && break
                    
                    if [[ -n "$L_IDX" ]]; then
                        LV_ESCOLHIDO=${LVS[$((L_IDX-1))]}
                        [[ -n "$LV_ESCOLHIDO" ]] && ALVO_LVM="/dev/mapper/$LV_ESCOLHIDO" || ALVO_LVM=""
                    fi
                    break
                done
                [[ ${L_IDX,,} == 'v' ]] && continue
            fi
        else
            MODO="RAW"
            ALVO_NOME="/dev/$DISCO"
            if lsblk -no FSTYPE "$ALVO_NOME" | grep -qi "LVM"; then
                HAS_LVM="yes"
                while true; do
                    header
                    echo "${YELLOW}Selecione o Logical Volume (LV) para expandir (MODO RAW LVM):${RESET}"
                    LVS=(); mapfile -t LVS < <(lsblk -ln -o NAME,TYPE "$ALVO_NOME" | grep "lvm" | awk '{print $1}')
                    for i in "${!LVS[@]}"; do
                        LV_SIZE=$(lsblk -no SIZE "/dev/mapper/${LVS[$i]}" 2>/dev/null || lsblk -no SIZE "/dev/${LVS[$i]}")
                        echo "  $((i+1))) ${LVS[$i]} ($LV_SIZE)"
                    done
                    echo "  v) Voltar ao Passo 2"
                    echo "----------------------------------------------------"
                    echo -n "Escolha o número: "; read L_IDX
                    [[ ${L_IDX,,} == 'v' ]] && break
                    
                    LV_ESCOLHIDO=${LVS[$((L_IDX-1))]}
                    [[ -n "$LV_ESCOLHIDO" ]] && ALVO_LVM="/dev/mapper/$LV_ESCOLHIDO" || ALVO_LVM=""
                    break
                done
                [[ ${L_IDX,,} == 'v' ]] && break
            fi
        fi

        header
        echo "${YELLOW}🚀 PASSO 4: Execução da Expansão${RESET}"
        echo "----------------------------------------------------"
        [[ "$MODO" == "RAW" ]] && echo -e "${GREEN}ℹ️ MODO RAW DETECTADO (Sem Partições)${RESET}"
        echo "  Alvo: $ALVO_NOME"
        [[ -n "$ALVO_LVM" ]] && echo "  LVM Alvo: $ALVO_LVM"
        [[ -n "$PONTO_MONTAGEM" ]] && echo "  Montado em: $PONTO_MONTAGEM"
        echo "  Espaço Livre: ${LIVRE_GB} GB"
        echo "----------------------------------------------------"
        echo "  1) Expandir 100% (Total)"
        echo "  2) Especificar um tamanho (ex: 500M, 1G)"
        echo "  v) Voltar ao Passo anterior"
        echo "----------------------------------------------------"
        echo -n "${BLUE}Escolha uma opção: ${RESET}"
        read OPT_EXP
        
        [[ ${OPT_EXP,,} == 'v' ]] && { ALVO_LVM=""; continue; }
        
        VALOR_EXPANSAO=""
        case $OPT_EXP in
            1) VALOR_EXPANSAO="100%" ;;
            2) 
                echo -n "${YELLOW}Digite o valor desejado (ex: 500M, 2G): ${RESET}"
                read VALOR_EXPANSAO
                [[ -z "$VALOR_EXPANSAO" ]] && { echo "Operação cancelada."; sleep 2; continue; }
                ;;
            *) echo "Opção inválida."; sleep 2; continue ;;
        esac

        if [[ "$MODO" == "PART" ]]; then
            progress 5 "Expandindo partição $ALVO_NOME via parted..."
            if [[ "$VALOR_EXPANSAO" == "100%" ]]; then
                sudo parted -s "/dev/$DISCO" resizepart "$PART_NUM" 100%
            else
                CUR_END=$(sudo parted -s "/dev/$DISCO" unit b print | grep -E "^ $PART_NUM" | awk '{print $3}' | tr -d 'B')
                ADD_B=0
                if [[ "$VALOR_EXPANSAO" =~ [Gg]$ ]]; then
                    ADD_B=$(echo "${VALOR_EXPANSAO%[Gg]*} * 1024 * 1024 * 1024" | bc)
                elif [[ "$VALOR_EXPANSAO" =~ [Mm]$ ]]; then
                    ADD_B=$(echo "${VALOR_EXPANSAO%[Mm]*} * 1024 * 1024" | bc)
                elif [[ "$VALOR_EXPANSAO" =~ ^[0-9]+$ ]]; then
                    ADD_B=$(echo "$VALOR_EXPANSAO * 1024 * 1024 * 1024" | bc)
                fi
                NEW_END=$((CUR_END + ADD_B))
                sudo parted -s "/dev/$DISCO" resizepart "$PART_NUM" "${NEW_END}b"
            fi
            sudo partprobe "/dev/$DISCO"
            sudo udevadm settle
        fi

        if [[ -n "$ALVO_LVM" ]]; then
            progress 5 "Expandindo Physical Volume (PV)..."
            sudo pvresize "$ALVO_NOME" >/dev/null 2>&1
            progress 5 "Expandindo Logical Volume (LV) $ALVO_LVM..."
            if [[ "$VALOR_EXPANSAO" == "100%" ]]; then
                sudo lvextend -l +100%FREE "$ALVO_LVM" >/dev/null 2>&1
            else
                # Se for apenas número, assume G
                [[ "$VALOR_EXPANSAO" =~ ^[0-9]+$ ]] && VALOR_EXPANSAO="${VALOR_EXPANSAO}G"
                sudo lvextend -L +"$VALOR_EXPANSAO" "$ALVO_LVM" >/dev/null 2>&1
            fi
            ALVO_FINAL="$ALVO_LVM"
        else
            ALVO_FINAL="$ALVO_NOME"
        fi

        FSTYPE=$(lsblk -no FSTYPE "$ALVO_FINAL" | head -n1 | xargs)
        [[ -z "$FSTYPE" ]] && FSTYPE=$(sudo blkid -s TYPE -o value "$ALVO_FINAL")
        
        progress 5 "Expandindo sistema de arquivos ($FSTYPE)..."
        case "$FSTYPE" in
            xfs) 
                sudo xfs_growfs "$ALVO_FINAL" >/dev/null 2>&1 
                ;;
            ext*) 
                # Para EXT4, o resize2fs é muito eficiente. 
                # Se for 100% ou LVM, não passamos tamanho (ele pega o máximo do device/LV)
                if [[ "$VALOR_EXPANSAO" == "100%" || -n "$ALVO_LVM" ]]; then
                    sudo resize2fs "$ALVO_FINAL"
                else
                    # Se for um tamanho específico em modo RAW/Partição
                    # O resize2fs interpreta o tamanho como o tamanho FINAL do sistema de arquivos.
                    # Se o usuário quer adicionar 20G, precisamos somar ao tamanho atual.
                    # Para evitar erros de 'On-line shrinking', vamos sempre tentar expandir para o máximo
                    # do dispositivo se o modo for expansão simples.
                    echo "${YELLOW}Aviso: Para EXT4 online, expandindo para o tamanho máximo disponível no dispositivo.${RESET}"
                    sudo resize2fs "$ALVO_FINAL"
                fi
                
                RESIZE_RET=$?
                if [ $RESIZE_RET -ne 0 ]; then
                    log_message "ERROR" "Falha ao expandir o sistema de arquivos EXT4 em $ALVO_FINAL (Exit Code: $RESIZE_RET)"
                    echo -e "\n${RED}❌ ERRO: Falha ao expandir o sistema de arquivos EXT4.${RESET}"
                    echo "O comando resize2fs retornou erro. Verifique as mensagens acima."
                    echo "Possíveis causas: sistema de arquivos sujo ou erro de redimensionamento online."
                    pause_nav
                    continue 2
                fi
                ;;
            *) echo "${YELLOW}Aviso: Sistema de arquivos '$FSTYPE' não suportado para expansão automática.${RESET}" ;;
        esac

        echo -e "\n${GREEN}${BOLD}🎉 SUCESSO! Expansão concluída.${RESET}"
        log_message "SUCCESS" "Expansão de $ALVO_FINAL concluída com sucesso."
        lsblk "$ALVO_FINAL"
        pause_nav
        break 2
    done
done
