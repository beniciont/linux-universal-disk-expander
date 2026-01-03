#!/bin/bash

# ==============================================================================
# EXPANSAO OCI LINUX
# Criado por: Benicio Neto
# Versão: 2.5.7 (PRODUÇÃO)
# Última Atualização: 03/01/2026
#
# HISTÓRICO DE VERSÕES:
# 1.0.0 a 2.5.6 - Evolução e correções de bugs.
# 2.5.7 (03/01/2026) - FIX: Exibição obrigatória e destacada do status final.
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
    if ! command -v sgdisk &>/dev/null; then
        log_message "INFO" "gdisk não encontrado. Tentando instalar..."
        echo "${YELLOW}Instalando ferramenta necessária (gdisk)...${RESET}"
        if command -v yum &>/dev/null; then
            sudo yum install -y gdisk >/dev/null 2>&1
        elif command -v apt-get &>/dev/null; then
            sudo apt-get update >/dev/null 2>&1
            sudo apt-get install -y gdisk >/dev/null 2>&1
        fi
    fi
}

# Função para traduzir e padronizar erros
friendly_error() {
    local raw_msg="$1"
    if echo "$raw_msg" | grep -qiE "matches existing size|nothing to do|NOCHANGE"; then
        echo "INALTERADO: O volume já possui o tamanho solicitado ou não há novo espaço."
    elif echo "$raw_msg" | grep -qiE "insufficient free space|not enough free space"; then
        echo "ERRO: Não há espaço livre disponível no disco físico para esta expansão."
    elif echo "$raw_msg" | grep -qi "no tools available.*gpt"; then
        echo "ERRO: Faltam ferramentas do sistema (gdisk) para manipular partições GPT."
    elif echo "$raw_msg" | grep -qi "no space left"; then
        echo "ERRO: Não foi encontrado espaço livre após a partição selecionada."
    elif echo "$raw_msg" | grep -qi "outside of device"; then
        echo "ERRO: O tamanho solicitado é maior do que o disco físico permite."
    elif echo "$raw_msg" | grep -qi "being used"; then
        echo "" # Silenciamos avisos de uso, pois a verificação de bytes é soberana
    else
        echo "ERRO TÉCNICO: $raw_msg"
    fi
}

# Função para obter o espaço não alocado (Espaço OCI)
get_unallocated_space() {
    local disk="/dev/$1"
    
    check_dependencies

    if command -v sgdisk &>/dev/null; then
        sudo sgdisk -e "$disk" >/dev/null 2>&1
    fi

    local disk_size_bytes=$(lsblk -bdno SIZE "$disk" | head -n1)
    local last_part_end=$(sudo parted -s "$disk" unit B print | grep -E "^ [0-9]+" | tail -n1 | awk '{print $3}' | tr -d 'B')
    
    if [[ -z "$last_part_end" ]]; then
        echo "scale=2; $disk_size_bytes / 1024 / 1024 / 1024" | bc
    else
        local free_bytes=$((disk_size_bytes - last_part_end))
        if [[ "$free_bytes" -lt 1048576 ]]; then
            echo "0"
        else
            echo "scale=2; $free_bytes / 1024 / 1024 / 1024" | bc
        fi
    fi
}

header() {
    clear
    echo "=================================="
    echo " EXPANSAO OCI LINUX v2.5.7 "
    echo " Criado por: Benicio Neto"
    echo " Versão: 2.5.7 (PRODUÇÃO)"
    echo " Última Atualização: 03/01/2026 "
    echo "=================================="
    echo
}

pause_nav() {
    echo
    echo -n "${YELLOW}[ENTER] continuar (v=voltar / q=sair): ${RESET}"
    read resp
    case ${resp,,} in
        'q') 
            log_message "INFO" "Usuário solicitou saída (q)."
            exit 0 ;;
        'v') 
            log_message "INFO" "Usuário solicitou voltar (v)."
            return 1 ;;
        *) return 0 ;;
    esac
}

progress() {
    local steps=$1 msg=$2
    echo "  > $msg"
    log_message "EXEC" "$msg"
    for ((i=1; i<=steps; i++)); do
        printf "    [%3d%%] " $((i*100/steps))
        sleep 0.5
        printf "\r               \r"
    done
    echo "  ${GREEN}[OK]${RESET} $msg"
}

# Início do Script
log_message "START" "Script iniciado."
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
    
    [[ ${DISCO,,} == 'q' ]] && log_message "INFO" "Saída no Passo 1." && exit 0
    if [[ -z "$DISCO" || ! -b "/dev/$DISCO" ]]; then
        echo "${RED}ERRO: Disco /dev/$DISCO não encontrado!${RESET}"
        log_message "ERROR" "Disco /dev/$DISCO não encontrado ou inválido."
        sleep 2; continue
    fi

    TAMANHO_ANTIGO=$(lsblk -bdno SIZE "/dev/$DISCO" | head -n1 | tr -d ' ')
    TAMANHO_ANTIGO_HUMANO=$(lsblk -dno SIZE "/dev/$DISCO" | head -n1)
    
    log_message "INFO" "Disco selecionado: /dev/$DISCO (Tamanho atual: $TAMANHO_ANTIGO_HUMANO)"
    echo -e "\n${GREEN}DISCO SELECIONADO: /dev/$DISCO ($TAMANHO_ANTIGO_HUMANO)${RESET}"
    pause_nav || continue

    # PASSO 2: RESCAN DO KERNEL
    while true; do
        header
        echo "${YELLOW}PASSO 2: Rescan do Kernel${RESET}"
        echo "=========================="
        
        progress 2 "Atualizando /dev/$DISCO via sysfs..."
        if [ -f "/sys/class/block/$DISCO/device/rescan" ]; then
            echo 1 | sudo tee "/sys/class/block/$DISCO/device/rescan" >/dev/null 2>&1
        fi
        
        progress 2 "Executando rescan iSCSI (OCI)..."
        sudo iscsiadm -m node -R >/dev/null 2>&1
        sudo iscsiadm -m session -R >/dev/null 2>&1
        
        progress 2 "Sincronizando tabela de partições..."
        sudo partprobe "/dev/$DISCO" >/dev/null 2>&1
        
        sleep 2

        TAMANHO_NOVO=$(lsblk -bdno SIZE "/dev/$DISCO" | head -n1 | tr -d ' ')
        TAMANHO_NOVO_HUMANO=$(lsblk -dno SIZE "/dev/$DISCO" | head -n1)

        ESPACO_OCI=$(get_unallocated_space "$DISCO")

        if [ "$TAMANHO_NOVO" -gt "$TAMANHO_ANTIGO" ] || (( $(echo "$ESPACO_OCI > 0" | bc -l) )); then
            log_message "SUCCESS" "Espaço OCI detectado: ${ESPACO_OCI}GB"
            echo -e "\n${GREEN}SUCESSO! Espaço novo detectado.${RESET}"
            echo "Tamanho do Disco: $TAMANHO_NOVO_HUMANO"
            echo "Espaço não alocado (OCI): ${ESPACO_OCI} GB"
            pause_nav && break || continue 2
        else
            log_message "WARN" "Rescan não detectou mudança no tamanho do disco ($TAMANHO_NOVO_HUMANO)."
            echo -e "\n${RED}AVISO: O tamanho do disco não mudou ($TAMANHO_NOVO_HUMANO).${RESET}"
            echo "--------------------------------------------------"
            echo "${BOLD}${YELLOW}ORIENTAÇÃO:${RESET}"
            echo "1. Valide na console da OCI se o disco realmente foi expandido."
            echo "2. Se já expandiu na console, tente a opção 'Rescan SCSI' abaixo."
            echo "--------------------------------------------------"
            echo -e "${CYAN}Escolha uma ação técnica:${RESET}"
            echo "1) Rescan SCSI  2) Tentar de novo  3) Seguir mesmo assim  v) Voltar  q) Sair"
            echo -n -e "\n${BLUE}Opção: ${RESET}"
            read OPT
            case ${OPT,,} in
                1) 
                    log_message "INFO" "Executando rescan-scsi-bus.sh"
                    if command -v rescan-scsi-bus.sh &>/dev/null; then sudo rescan-scsi-bus.sh; fi; sleep 2; continue ;;
                2) continue ;;
                3) 
                   ESPACO_OCI=$(get_unallocated_space "$DISCO")
                   log_message "INFO" "Usuário forçou prosseguimento. Espaço OCI: ${ESPACO_OCI}GB"
                   echo -e "\n${YELLOW}Forçando prosseguimento...${RESET}"
                   echo "Espaço não alocado detectado: ${ESPACO_OCI} GB"
                   sleep 1; break ;;
                'v') continue 2 ;;
                'q') exit 0 ;;
                *) continue ;;
            esac
        fi
    done

    # PASSO 3: ESTRUTURA E TAMANHO
    header
    echo "${CYAN}PASSO 3: Estrutura e Definição de Tamanho${RESET}"
    echo "======================"
    echo "${BOLD}Utilização Atual das Partições em /dev/$DISCO:${RESET}"
    PARTS_LIST=$(lsblk -ln -o NAME,TYPE "/dev/$DISCO" | grep "part" | awk '{print $1}')
    for p in $PARTS_LIST; do
        MOUNT_P=$(lsblk -no MOUNTPOINT "/dev/$p" | tr -d ' ')
        if [[ -n "$MOUNT_P" && "$MOUNT_P" != "" && "$MOUNT_P" != "[SWAP]" ]]; then
            df -h "$MOUNT_P" | tail -n1 | awk '{printf "  %-10s %-5s %-5s %-5s %-4s %s\n", $1, $2, $3, $4, $5, $6}'
        fi
    done
    echo "----------------------"
    lsblk "/dev/$DISCO" -f
    echo "======================"
    
    # AVISO DE ESPAÇO 0 (Não bloqueia mais, apenas avisa e pergunta)
    if (( $(echo "$ESPACO_OCI <= 0" | bc -l) )); then
        echo -e "\n${RED}${BOLD}ATENÇÃO: O script não detectou espaço livre (OCI) neste disco.${RESET}"
        echo "Se você prosseguir, a expansão provavelmente falhará ou não mudará nada."
        echo -n -e "\n${YELLOW}Deseja tentar mesmo assim? (s/n): ${RESET}"
        read TENTAR
        if [[ ${TENTAR,,} != 's' ]]; then
            log_message "INFO" "Usuário desistiu da expansão sem espaço detectado."
            continue
        fi
        log_message "WARN" "Usuário forçou expansão com 0GB detectados em /dev/$DISCO."
    fi

    IS_LVM=$(lsblk -no FSTYPE "/dev/$DISCO" | grep -i "LVM")
    
    if [[ -n "$IS_LVM" ]]; then
        MODO="LVM"
        REAL_LV=$(lsblk -ln -o NAME,TYPE "/dev/$DISCO" | grep "lvm" | head -n1 | awk '{print $1}')
        ALVO_NOME="/dev/mapper/$REAL_LV"
        MOUNT=$(lsblk -ln -o MOUNTPOINT "/dev/$DISCO" | grep "/" | head -n1)
        TYPE=$(lsblk -ln -o FSTYPE "/dev/$DISCO" | grep -v "LVM" | head -n1)
        
        echo -e "\n${YELLOW}ESTRUTURA LVM DETECTADA.${RESET}"
        echo "Espaço novo disponível (OCI): ${ESPACO_OCI} GB"
        echo -e "\n${BLUE}Quanto deseja expandir em $ALVO_NOME?${RESET}"
        echo "1) Tudo (Usar os ${ESPACO_OCI}GB novos)"
        echo "2) Personalizado (Ex: 500M, 5G)"
        echo -n "Escolha: "
        read SIZE_OPT
        if [[ "$SIZE_OPT" == "2" ]]; then
            echo -n "Digite o valor (ex: 500M ou 5G): "
            read VALOR
            [[ $VALOR != +* ]] && VALOR="+$VALOR"
            TAMANHO_EXPANSAO="$VALOR"
            LVM_PARAM="-L"
        else
            TAMANHO_EXPANSAO="+100%FREE"
            LVM_PARAM="-l"
        fi
    else
        MODO="PART"
        PARTS=$(lsblk -ln -o NAME "/dev/$DISCO" | grep -E "^${DISCO}p?[0-9]+")
        if [[ -n "$PARTS" ]]; then
            SUGESTAO=$(echo "$PARTS" | paste -sd "/" -)
            echo -n -e "\n${BLUE}Qual partição expandir? ($SUGESTAO): ${RESET}"
            read PART
            [[ ${PART,,} == 'v' ]] && continue
            
            PART_NUM=$(echo "$PART" | grep -oE "[0-9]+$" | tail -1)
            MOUNT=$(lsblk -no MOUNTPOINT "/dev/$PART" 2>/dev/null | tr -d ' ')
            TYPE=$(lsblk -no FSTYPE "/dev/$PART" 2>/dev/null)
            ALVO_NOME="/dev/$PART"
            
            echo -e "\n${YELLOW}ESTRUTURA DE PARTIÇÃO PADRÃO DETECTADA.${RESET}"
            echo "Espaço novo disponível (OCI): ${ESPACO_OCI} GB"
            echo -e "\n${BLUE}Quanto deseja expandir em $ALVO_NOME?${RESET}"
            echo "1) Tudo (Usar todo o espaço novo)"
            echo "2) Personalizado (Ex: 500M, 5G)"
            echo -n "Escolha: "
            read SIZE_OPT
            if [[ "$SIZE_OPT" == "2" ]]; then
                echo -n "Digite o valor (ex: 500M ou 5G): "
                read VALOR
                VALOR_LIMPO=$(echo "$VALOR" | tr -d '+')
                
                ATUAL_FIM=$(sudo parted -s "/dev/$DISCO" unit B print | grep -E "^ $PART_NUM" | awk '{print $3}' | tr -d 'B')
                MULT=1
                case ${VALOR_LIMPO: -1} in
                    [Gg]) MULT=$((1024*1024*1024)) ;;
                    [Mm]) MULT=$((1024*1024)) ;;
                    [Tt]) MULT=$((1024*1024*1024*1024)) ;;
                esac
                NUM_VALOR=$(echo "$VALOR_LIMPO" | grep -oE "[0-9]+")
                ADD_BYTES=$((NUM_VALOR * MULT))
                NOVO_FIM=$((ATUAL_FIM + ADD_BYTES))
                
                TAMANHO_EXPANSAO="${NOVO_FIM}B"
                METODO_PART="parted"
            else
                TAMANHO_EXPANSAO="100%"
                METODO_PART="growpart"
            fi
        else
            echo "${RED}ERRO: Nenhuma estrutura reconhecida!${RESET}"; sleep 2; continue
        fi
    fi
    
    # --- CAPTURA DO TAMANHO INICIAL ---
    if [[ -n "$MOUNT" && "$MOUNT" != "livre" ]]; then
        FS_SIZE_BEFORE=$(df -B1 "$MOUNT" | tail -n1 | awk '{print $2}')
    else
        FS_SIZE_BEFORE=$(lsblk -bdno SIZE "$ALVO_NOME" | head -n1)
    fi

    pause_nav || continue

    # PASSO 4: EXECUÇÃO DA EXPANSÃO
    header
    echo "${GREEN}PASSO 4: Executando expansão ($MODO)${RESET}"
    echo "================================"
    
    EXP_SUCCESS=0
    ERROR_DETAIL=""

    if [[ "$MODO" == "LVM" ]]; then
        progress 2 "pvresize /dev/$DISCO..."
        sudo pvresize "/dev/$DISCO" >/dev/null 2>&1
        
        progress 2 "lvextend $LVM_PARAM $TAMANHO_EXPANSAO $ALVO_NOME..."
        CMD_OUT=$(sudo lvextend "$LVM_PARAM" "$TAMANHO_EXPANSAO" "$ALVO_NOME" 2>&1)
        if [[ $? -eq 0 ]]; then
            EXP_SUCCESS=1
            TARGET_FS="$ALVO_NOME"
        else
            ERROR_DETAIL=$(friendly_error "$CMD_OUT")
            EXP_SUCCESS=0
        fi
    else
        if [[ "$METODO_PART" == "parted" ]]; then
            progress 2 "parted resizepart $PART_NUM $TAMANHO_EXPANSAO..."
            CMD_OUT=$(echo "Yes" | sudo parted "/dev/$DISCO" resizepart "$PART_NUM" "$TAMANHO_EXPANSAO" 2>&1)
            if [[ $? -eq 0 ]]; then
                EXP_SUCCESS=1
            else
                ERROR_DETAIL=$(friendly_error "$CMD_OUT")
                EXP_SUCCESS=0
            fi
        else
            progress 2 "growpart /dev/$DISCO $PART_NUM..."
            CMD_OUT=$(sudo growpart "/dev/$DISCO" "$PART_NUM" 2>&1)
            if [[ $? -eq 0 ]]; then
                EXP_SUCCESS=1
            else
                log_message "WARN" "growpart falhou. Tentando fallback com parted..."
                progress 2 "Fallback: parted resizepart $PART_NUM 100%..."
                CMD_OUT=$(echo "Yes" | sudo parted "/dev/$DISCO" resizepart "$PART_NUM" 100% 2>&1)
                if [[ $? -eq 0 ]]; then
                    EXP_SUCCESS=1
                else
                    if echo "$CMD_OUT" | grep -q "NOCHANGE"; then
                        EXP_SUCCESS=2
                    else
                        ERROR_DETAIL=$(friendly_error "$CMD_OUT")
                        EXP_SUCCESS=0
                    fi
                fi
            fi
        fi
        
        if [[ $EXP_SUCCESS -ge 1 ]]; then
            sudo partprobe "/dev/$DISCO" >/dev/null 2>&1
            TARGET_FS="$ALVO_NOME"
        fi
    fi

    if [[ $EXP_SUCCESS -ge 1 ]]; then
        if [[ -n "$MOUNT" && "$MOUNT" != "livre" ]]; then
            if [[ "$TYPE" == "xfs" ]]; then
                progress 2 "xfs_growfs $MOUNT..."
                sudo xfs_growfs "$MOUNT" >/dev/null 2>&1
            else
                progress 2 "resize2fs $TARGET_FS..."
                sudo resize2fs "$TARGET_FS" >/dev/null 2>&1
            fi
        fi
        
        # Verificação Final de Tamanho
        if [[ -n "$MOUNT" && "$MOUNT" != "livre" ]]; then
            FS_SIZE_AFTER=$(df -B1 "$MOUNT" | tail -n1 | awk '{print $2}')
        else
            FS_SIZE_AFTER=$(lsblk -bdno SIZE "$ALVO_NOME" | head -n1)
        fi

        # LÓGICA DE RESULTADO FINAL (v2.5.7)
        if [[ "$FS_SIZE_AFTER" -gt "$FS_SIZE_BEFORE" ]]; then
            FINAL_MSG="${GREEN}${BOLD}SUCESSO! Expansão concluída.${RESET}"
            ERROR_DETAIL=""
        else
            FINAL_MSG="${YELLOW}${BOLD}INALTERADO: O tamanho final não mudou. Verifique se há espaço real no disco físico (OCI Console).${RESET}"
            ERROR_DETAIL=""
        fi
    else
        FINAL_MSG="${RED}${BOLD}$ERROR_DETAIL${RESET}"
    fi

    # RESULTADO FINAL
    header
    echo "${GREEN}RESULTADO FINAL${RESET}"
    echo "=================="
    lsblk -f "$ALVO_NOME"
    if [[ -n "$MOUNT" && "$MOUNT" != "livre" ]]; then
        echo -e "\n${CYAN}Tamanho atual de $MOUNT:${RESET}"
        df -h "$MOUNT" | grep -E "Filesystem|$ALVO_NOME"
    fi
    
    # --- EXIBIÇÃO OBRIGATÓRIA E DESTACADA ---
    echo -e "\n--------------------------------------------------"
    echo -e "STATUS: $FINAL_MSG"
    echo -e "--------------------------------------------------"
    
    echo -e "\n${BLUE}Deseja realizar outra operação?${RESET}"
    pause_nav || continue
    exit 0
done
