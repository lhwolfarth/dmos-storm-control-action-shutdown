#!/bin/bash

# Armazena caminho do diretório do script
SCRIPT_PATH=$(dirname "$0");
CONFIG_FILE="$SCRIPT_PATH/dmos-storm-control-action-shutdown.conf"
LOG_FILE="$SCRIPT_PATH/dmos-storm-control-action-shutdown.log"
STATUS_FILE="$SCRIPT_PATH/dmos-storm-control-action-shutdown.csv"
PHP_FILE="/var/www/html/dmos-storm-control-action-shutdown.php"

# Função para verificar se o sshpass está instalado
check_sshpass() {
    if ! command -v sshpass &> /dev/null; then
        echo ""
        echo "O sshpass não está instalado e o script depende desse programa. Deseja instala-lo agora? (sim/não) (yes/no)"
        echo ""
        read answer
        case "$answer" in
            [SsYy]|[Ss][Ii][Mm]|[Yy][Ee][Ss])
                echo "Tentando instalar via apt..."
                sudo apt update
                sudo apt install -y sshpass
                ;;
            [Nn]|[Nn][Aa][Oo]|[Nn][Oo])
                echo "Você optou por não instalar o sshpass."
                ;;
            *)
                echo "Entrada inválida. Por favor, responda 'sim' ou 'não'."
                ;;
        esac
    fi
}

# Chamada da função
check_sshpass

# Definindo valores padrão
TEST=0
DEBUG=0

# Função para exibir a mensagem de uso
function usage() {
  echo ""
  echo "Este script aplica o comando shutdown na interface Backup de um determinado anel caso o Storm de Broadcast ou Multicast ocorra no anel." 
  echo "Funcionamento: Como fator de decisão o script compara o PPS de Broadcast Input ou Multicast Input com o limitar configurado no arquivo '$CONFIG_FILE' e caso um dos valores seja violado na interface Main ou Backup a interface Backup será colocada em shutdown. As leituras são feitas por SNMPv2 e a configuração de shutdown é realizada por SSH."
  echo ""
  echo "Uso: $0 -h -t"
  echo ""
  echo "Opções:"
  echo "  -h               Exibe ajuda"
  echo "  -t               Modo teste, o comando "shutdown" não será aplicado mesmo que os limiares de PPP sejam atingidos (opcional)"
  echo "  -d               Habilita o modo debug (opcional)"
  echo ""
  echo "Exemplo de uso (para realizar testes ou debug):"
  echo "  $0 -t -d"
  echo ""
  echo "Exemplo de uso (para aplicar o shutdown caso necessário):"
  echo " $0"
  echo ""
  exit 1
}

# Parse das flags
while getopts "htd" opt; do
  case $opt in
    h) usage ;;
    t) TEST=1 ;;
    d) DEBUG=1 ;;
    *) usage ;;
  esac
done

# Extrair informações de configuração do arquivo
ssh_user=$(grep '^ssh-user' $CONFIG_FILE | cut -d':' -f2)
ssh_password=$(grep '^ssh-password' $CONFIG_FILE | cut -d':' -f2)
snmp_community=$(grep '^snmp-v2c-community' $CONFIG_FILE | cut -d':' -f2)
ssh_port=$(grep "ssh-port" $CONFIG_FILE | grep -v "#" | cut -d':' -f2)
if [[ -z $ssh_port ]]; then ssh_port="22"; fi
period=$(grep '^period' $CONFIG_FILE | cut -d':' -f2)

check_ssh_connectivity() {

    # Verifica se há conectividade IP
    if ping -c 1 $1 >/dev/null; then
        echo "$(date "+%Y-%m-%d %T") - A conectividade IP está OK."
        # Tenta autenticar via SSH
        if sshpass -p "$ssh_password" ssh -o StrictHostKeyChecking=no -p "$ssh_port" "$ssh_user"@"$1" true >/dev/null 2>&1; then
            echo "$(date "+%Y-%m-%d %T") - SSH autenticado com sucesso."
        else
            echo "$(date "+%Y-%m-%d %T") - Falha na autenticação SSH. Verifique usuario e senha."
            exit 1  # Interrompe o script se a autenticação SSH falhar
        fi
    else
        echo "$(date "+%Y-%m-%d %T") - Falha na conectividade IP."
        exit 1  # Interrompe o script se a conectividade IP falhar
    fi
}

check_snmp_connectivity() {

    snmpwalk -v 2c -c "$snmp_community" "$1" ".1.3.6.1.2.1.1.3.0" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "$(date "+%Y-%m-%d %T") - Conectividade SNMP bem-sucedida."
    else
        echo "$(date "+%Y-%m-%d %T") - Falha na conectividade SNMP."
    fi
}


# Função para listar os anéis do arquivo
listar_aneis() {
    # Extrair os números de anel únicos do arquivo
    aneis=$(grep '^anel-' $CONFIG_FILE | cut -d'-' -f2 | cut -d'-' -f1 | uniq)
}

# Função para obter o IP do switch relacionado a um determinado anel
obter_ip_switch() {
    # Argumento: Nome do anel
    local anel="$1"

    # Extrair o IP do switch para o anel especificado
    switch_ip=$(grep "$anel-switch-ip" $CONFIG_FILE | cut -d':' -f2)

    # Imprimir o IP do switch
    #echo "IP do Switch para o Anel $anel: $switch_ip"
}

# Função para obter o valor de max-pps de multicast e broadcast para cada anel
obter_max_pps() {
    # Argumento: Nome do anel
    local anel="$1"

    # Extrair o valor de max-pps de multicast e broadcast para o anel especificado
    broadcast_max_pps=$(grep "$anel-broadcast-max-pps" $CONFIG_FILE | grep -v "#" | cut -d':' -f2 )
    multicast_max_pps=$(grep "$anel-multicast-max-pps" $CONFIG_FILE | grep -v "#" | cut -d':' -f2 )
}

# Função para aplicar o comando shutdown na interface backup
aplicar_shutdown_backup() {
    # Argumento: Nome do anel
    local anel="$1"

    # Extrair a interface backup para o anel especificado
    backup=$(grep "$anel-backup" $CONFIG_FILE | cut -d':' -f2)
    interface=$(echo "$backup" | sed 's#-1# 1#g')

    # Acessar o equipamento por SSH e aplicar o comando shutdown na interface backup
    echo "$(date "+%Y-%m-%d %T") : Switch $switch_ip : $anel : Aplicando shutdown na interface Backup ($backup) do anel $name:"
    if [ $TEST -eq 1 ]; then
       echo "$(date "+%Y-%m-%d %T") : Switch $switch_ip : $anel : COMMAND = config ; interface $interface ; shutdown ; commit : MODO TESTE ATIVO, O SHUTDOWN NÃO SERÁ APLICADO..."
    else
       switch_log=$(sshpass -p "$ssh_password" ssh -o StrictHostKeyChecking=no -p "$ssh_port" "$ssh_user"@"$switch_ip" "config ; interface $interface ; shutdown ; commit label STORM-CTRL comment SHUT-$backup-$2" 2>/dev/null)
       echo "$(date "+%Y-%m-%d %T") : Switch $switch_ip : $anel : command = config ; interface $interface ; shutdown ; commit : $switch_log"
    fi
}

# Função para calcular o PPS broadcast e multicast das interfaces main e backup para cada anel
calcular_pps() {
# Nome do arquivo para armazenar os status dos ONUs

    # Argumento 1: Nome do anel
    local anel="$1"

    # Obter o IP do switch para o anel especificado que será armazenado na variável "switch_ip"
    obter_ip_switch "$anel"

    # Obter o PPS Broadcast e Multicast máximo configurado para o anel
    obter_max_pps "$anel"

    # Nome do diretório para armazenar os arquivos
    data_dir="leituras_switch_${switch_ip//./_}"
    # Verifica se o diretório de dados existe, se não, cria um novo
    if [ ! -d "$data_dir" ]; then
      mkdir "$data_dir"
    fi

    # Extrair interfaces main e backup para o anel especificado
    main=$(grep "$anel-main" $CONFIG_FILE | cut -d':' -f2)
    backup=$(grep "$anel-backup" $CONFIG_FILE | cut -d':' -f2)
    name=$(grep "$anel-name" $CONFIG_FILE | cut -d':' -f2)

    # Obter OID das interfaces main e backup
    oid_main=$(snmpbulkwalk -c "$snmp_community" -v2c "$switch_ip" 1.3.6.1.2.1.31.1.1.1.1 -One | grep "$main$" | cut -d '=' -f1 | cut -d '.' -f13)
    oid_backup=$(snmpbulkwalk -c "$snmp_community" -v2c "$switch_ip" 1.3.6.1.2.1.31.1.1.1.1 -One | grep "$backup$" | cut -d '=' -f1 | cut -d '.' -f13)

    # Exibir informações de debug
    if [ $DEBUG -eq 1 ]; then
       echo ""
       echo "------- Parâmetros -------"
       echo "Anel:                            $1"
       echo "Nome do Anel:                    $name"
       echo "Usuário:                         $ssh_user"
       echo "Senha:                           $ssh_port"
       echo "Endereço IP:                     $switch_ip"
       echo "Porta SSH:                       $ssh_port"
       echo "SNMP Community:                  $snmp_community"
       echo "Período entre as leituras SNMP:  $period"
       echo "Interface Main:                  $main"
       echo "Interface Main OID Broadcast:    .1.3.6.1.2.1.31.1.1.1.3.$oid_main"
       echo "Interface Main OID Multicast:    .1.3.6.1.2.1.31.1.1.1.2.$oid_main"
       echo "Interface Backup:                $backup"
       echo "Interface Backup OID Broadcast:  .1.3.6.1.2.1.31.1.1.1.3.$oid_backup"
       echo "Interface Backup OID Multicast:  .1.3.6.1.2.1.31.1.1.1.2.$oid_backup"
       echo "Modo debug:                      ativado"
       echo ""
       # Verificar conectividade e autenticação SSH
       check_ssh_connectivity $switch_ip
       check_snmp_connectivity $switch_ip
    fi

    # Obter status administrativo e operacional das interfaces
    admin_state_main=$(snmpbulkwalk -c "$snmp_community" -v2c "$switch_ip" .1.3.6.1.2.1.2.2.1.7.$oid_main -One | cut -d' ' -f4)
    oper_state_main=$(snmpbulkwalk -c "$snmp_community" -v2c "$switch_ip" .1.3.6.1.2.1.2.2.1.8.$oid_main -One | cut -d' ' -f4)
    admin_state_backup=$(snmpbulkwalk -c "$snmp_community" -v2c "$switch_ip" .1.3.6.1.2.1.2.2.1.7.$oid_backup -One | cut -d' ' -f4)
    oper_state_backup=$(snmpbulkwalk -c "$snmp_community" -v2c "$switch_ip" .1.3.6.1.2.1.2.2.1.8.$oid_backup -One | cut -d' ' -f4)
    if [ $admin_state_main -eq 1 ]; then admin_state_main="Up"; else admin_state_main="Down";fi
    if [ $oper_state_main -eq 1 ]; then oper_state_main="Up"; else oper_state_main="Down";fi
    if [ $admin_state_backup -eq 1 ]; then admin_state_backup="Up"; else admin_state_backup="Down";fi
    if [ $oper_state_backup -eq 1 ]; then oper_state_backup="Up"; else oper_state_backup="Down";fi

    # Obter a leitura atual de broadcast e multicast para as interfaces principais e de backup
    leitura_atual_broadcast_main_raw=$(snmpbulkwalk -c "$snmp_community" -v2c "$switch_ip" .1.3.6.1.2.1.31.1.1.1.3.$oid_main -One | cut -d' ' -f4 | awk -v timestamp=$(date +%s) '{print $1 ";" timestamp }')
    leitura_atual_multicast_main_raw=$(snmpbulkwalk -c "$snmp_community" -v2c "$switch_ip" .1.3.6.1.2.1.31.1.1.1.2.$oid_main -One | cut -d' ' -f4 | awk -v timestamp=$(date +%s) '{print $1 ";" timestamp }')
    leitura_atual_broadcast_backup_raw=$(snmpbulkwalk -c "$snmp_community" -v2c "$switch_ip" .1.3.6.1.2.1.31.1.1.1.3.$oid_backup -One | cut -d' ' -f4 | awk -v timestamp=$(date +%s) '{print $1 ";" timestamp }')
    leitura_atual_multicast_backup_raw=$(snmpbulkwalk -c "$snmp_community" -v2c "$switch_ip" .1.3.6.1.2.1.31.1.1.1.2.$oid_backup -One | cut -d' ' -f4 | awk -v timestamp=$(date +%s) '{print $1 ";" timestamp }')
    leitura_atual_broadcast_main=$(echo "$leitura_atual_broadcast_main_raw" | cut -d ';' -f1)
    leitura_atual_multicast_main=$(echo "$leitura_atual_multicast_main_raw" | cut -d ';' -f1)
    leitura_atual_broadcast_backup=$(echo "$leitura_atual_broadcast_backup_raw" | cut -d ';' -f1)
    leitura_atual_multicast_backup=$(echo "$leitura_atual_multicast_backup_raw" | cut -d ';' -f1)
    timestamp_atual_broadcast_main=$(echo "$leitura_atual_broadcast_main_raw" | cut -d ';' -f2)
    timestamp_atual_multicast_main=$(echo "$leitura_atual_multicast_main_raw" | cut -d ';' -f2)
    timestamp_atual_broadcast_backup=$(echo "$leitura_atual_broadcast_backup_raw" | cut -d ';' -f2)
    timestamp_atual_multicast_backup=$(echo "$leitura_atual_multicast_backup_raw" | cut -d ';' -f2)

    # Obter a leitura anterior de broadcast e multicast para as interfaces principais e de backup
    if [ ! -f "$data_dir/leitura_anterior_broadcast-$switch_ip-${anel}_main.txt" ]; then
     echo "$leitura_atual_broadcast_main_raw" > "$data_dir/leitura_anterior_broadcast-$switch_ip-${anel}_main.txt"; brd_div_main=1
    fi
    if [ ! -f "$data_dir/leitura_anterior_multicast-$switch_ip-${anel}_main.txt" ]; then
     echo "$leitura_atual_multicast_main_raw" > "$data_dir/leitura_anterior_multicast-$switch_ip-${anel}_main.txt"; mlt_div_main=1
    fi
    if [ ! -f "$data_dir/leitura_anterior_broadcast-$switch_ip-${anel}_backup.txt" ]; then
     echo "$leitura_atual_broadcast_backup_raw" > "$data_dir/leitura_anterior_broadcast-$switch_ip-${anel}_backup.txt"; brd_div_backup=1
    fi
    if [ ! -f "$data_dir/leitura_anterior_multicast-$switch_ip-${anel}_backup.txt" ]; then
     echo "$leitura_atual_multicast_backup_raw" > "$data_dir/leitura_anterior_multicast-$switch_ip-${anel}_backup.txt"; mlt_div_backup=1
    fi
    leitura_anterior_broadcast_main=$(cat "$data_dir/leitura_anterior_broadcast-$switch_ip-${anel}_main.txt" | cut -d ';' -f1)
    leitura_anterior_multicast_main=$(cat "$data_dir/leitura_anterior_multicast-$switch_ip-${anel}_main.txt" | cut -d ';' -f1)
    leitura_anterior_broadcast_backup=$(cat "$data_dir/leitura_anterior_broadcast-$switch_ip-${anel}_backup.txt" | cut -d ';' -f1)
    leitura_anterior_multicast_backup=$(cat "$data_dir/leitura_anterior_multicast-$switch_ip-${anel}_backup.txt" | cut -d ';' -f1)
    timestamp_anterior_broadcast_main=$(cat "$data_dir/leitura_anterior_broadcast-$switch_ip-${anel}_main.txt" | cut -d ';' -f2)
    timestamp_anterior_multicast_main=$(cat "$data_dir/leitura_anterior_multicast-$switch_ip-${anel}_main.txt" | cut -d ';' -f2)
    timestamp_anterior_broadcast_backup=$(cat "$data_dir/leitura_anterior_broadcast-$switch_ip-${anel}_main.txt" | cut -d ';' -f2)
    timestamp_anterior_multicast_backup=$(cat "$data_dir/leitura_anterior_multicast-$switch_ip-${anel}_main.txt" | cut -d ';' -f2)

    # Calcular o PPS broadcast e multicast das interfaces principais e de backup
    pps_broadcast_main=$(( ($leitura_atual_broadcast_main - $leitura_anterior_broadcast_main) / ($brd_div_main + $timestamp_atual_broadcast_main - $timestamp_anterior_broadcast_main) ))
    pps_multicast_main=$(( ($leitura_atual_multicast_main - $leitura_anterior_multicast_main) / ($mlt_div_main + $timestamp_atual_multicast_main - $timestamp_anterior_multicast_main) ))
    pps_broadcast_backup=$(( ($leitura_atual_broadcast_backup - $leitura_anterior_broadcast_backup) / ($brd_div_backup + $timestamp_atual_broadcast_backup - $timestamp_anterior_broadcast_backup) ))
    pps_multicast_backup=$(( ($leitura_atual_multicast_backup - $leitura_anterior_multicast_backup) / ($mlt_div_backup + $timestamp_atual_multicast_backup - $timestamp_anterior_multicast_backup) ))

    # Imprimir o PPS broadcast e multicast das interfaces principais e de backup
    if [[ -z $broadcast_max_pps ]]; then broadcast_max_pps="desabilitado"; pps_broad=""; else pps_broad="pps"; fi
    if [[ -z $multicast_max_pps ]]; then multicast_max_pps="desabilitado"; pps_mult=""; else pps_mult="pps"; fi
    if [ $TEST -eq 1 ]; then
     echo ""
     echo "$(date "+%Y-%m-%d %T") : Switch $switch_ip : $anel : PPS Broadcast da interface Main   : ($main) : (admin= $admin_state_main) : (oper= $oper_state_main) : $pps_broadcast_main pps (Limiar $broadcast_max_pps $pps_broad)"
     echo "$(date "+%Y-%m-%d %T") : Switch $switch_ip : $anel : PPS Multicast da interface Main   : ($main) : (admin= $admin_state_main) : (oper= $oper_state_main) : $pps_multicast_main pps (Limiar $multicast_max_pps $pps_mult)"
     echo "$(date "+%Y-%m-%d %T") : Switch $switch_ip : $anel : PPS Broadcast da interface Backup : ($backup) : (admin= $admin_state_backup) : (oper= $oper_state_backup) : $pps_broadcast_backup pps (Limiar $broadcast_max_pps $pps_broad)"
     echo "$(date "+%Y-%m-%d %T") : Switch $switch_ip : $anel : PPS Multicast da interface Backup : ($backup) : (admin= $admin_state_backup) : (oper= $oper_state_backup) : $pps_multicast_backup pps (Limiar $multicast_max_pps $pps_mult)"
    fi

    # Verificar se o PPS de broadcast ou multicast para pelo menos uma interface de backup é maior que o max-pps especificado
    if [[ $pps_broadcast_main -gt $broadcast_max_pps ]] || [[ $pps_broadcast_backup -gt $broadcast_max_pps ]] && [[ ! $broadcast_max_pps =~ "desabilitado" ]]; then
      if [[ $pps_broadcast_main -gt $broadcast_max_pps ]]; then
        echo "" | tee -a $LOG_FILE
        echo "$(date "+%Y-%m-%d %T") : Switch $switch_ip : $anel : PPS Broadcast da interface Main ($main) é maior que o Limiar de PPS especificado ($pps_broadcast_main/$broadcast_max_pps)." | tee -a $LOG_FILE 
        aplicar_shutdown_backup "$anel" "main-$pps_broadcast_main-pps-brdcst" | tee -a $LOG_FILE
      fi
      if [[ $pps_broadcast_backup -gt $broadcast_max_pps ]]; then
        echo "" | tee -a $LOG_FILE
        echo "$(date "+%Y-%m-%d %T") : Switch $switch_ip : $anel : PPS Broadcast da interface Backup ($backup) é maior que o Limiar de PPS especificado ($pps_broadcast_backup/$broadcast_max_pps)." | tee -a  $LOG_FILE 
        aplicar_shutdown_backup "$anel" "backup-$pps_broadcast_backup-pps-brdcst" | tee -a $LOG_FILE
      fi
    fi

    if [[ $pps_multicast_main -gt $multicast_max_pps ]] || [[ $pps_multicast_backup -gt $multicast_max_pps ]] && [[ ! $multicast_max_pps =~ "desabilitado" ]]; then
      if [[ $pps_multicast_main -gt $multicast_max_pps ]]; then
        echo "" | tee -a $LOG_FILE
        echo "$(date "+%Y-%m-%d %T") : Switch $switch_ip : $anel : PPS Multicast da interface Main ($main) é maior que o Limiar de PPS especificado ($pps_multicast_main/$multicast_max_pps)." | tee -a $LOG_FILE
        aplicar_shutdown_backup "$anel" "main-$pps_multicast_main-pps-mltcst" | tee -a $LOG_FILE
      fi
      if [[ $pps_multicast_backup -gt $multicast_max_pps ]]; then
        echo "" | tee -a $LOG_FILE
        echo "$(date "+%Y-%m-%d %T") : Switch $switch_ip : $anel : PPS Multicast da interface Backup ($backup) é maior que o Limiar de PPS especificado ($pps_multicast_backup/$multicast_max_pps)." | tee -a $LOG_FILE
        aplicar_shutdown_backup "$anel" "backup-$pps_multicast_backup-pps-mltcst" | tee -a $LOG_FILE
      fi
    fi

    # Atualizar as leituras anteriores com as leituras atuais
    echo "$leitura_atual_broadcast_main_raw" > "$data_dir/leitura_anterior_broadcast-$switch_ip-${anel}_main.txt"
    echo "$leitura_atual_multicast_main_raw" > "$data_dir/leitura_anterior_multicast-$switch_ip-${anel}_main.txt"
    echo "$leitura_atual_broadcast_backup_raw" > "$data_dir/leitura_anterior_broadcast-$switch_ip-${anel}_backup.txt"
    echo "$leitura_atual_multicast_backup_raw" > "$data_dir/leitura_anterior_multicast-$switch_ip-${anel}_backup.txt"
}

# Função que chama as funções para listar os anéis e a função para calcular o PPS e aplicar o shutdown caso o broadcast ou multicast seja maior que o limiar configurado
storm_control_action_shutdown() {
listar_aneis
aneis_count=$(echo "$aneis" | wc -l)
i=1
 # Cria CSV com os status
 echo "Anel ID;Name;Switch IP;Interface;Main/Backup;Admin State;Oper State;Broadcast/Multicast;PPS;Max PPS" > $STATUS_FILE 
while [ $i -le $aneis_count ]; do
   anel_id=$(echo "$aneis" | sed "${i}q;d")
   calcular_pps "anel-$anel_id"
   #Atualiza CSV com o status individual de cada interface
   echo "$anel_id;$name;$switch_ip;$main;Main;$admin_state_main;$oper_state_main;Broadcast;$pps_broadcast_main;$broadcast_max_pps" >> $STATUS_FILE
   echo "$anel_id;$name;$switch_ip;$main;Main;$admin_state_main;$oper_state_main;Multicast;$pps_multicast_main;$multicast_max_pps" >> $STATUS_FILE
   echo "$anel_id;$name;$switch_ip;$backup;Backup;$admin_state_backup;$oper_state_backup;Broadcast;$pps_broadcast_backup;$broadcast_max_pps" >> $STATUS_FILE
   echo "$anel_id;$name;$switch_ip;$backup;Backup;$admin_state_backup;$oper_state_backup;Multicast;$pps_multicast_backup;$multicast_max_pps" >> $STATUS_FILE
#   echo "-;-;-;-;-;-;-;-;-;-" >>  $STATUS_FILE
   (( i++ ))
done
}

create_php() {

echo "<?php \$data = array(" > $PHP_FILE
awk -F ';' '{
    if (NR > 1) {
        printf "[%s, \"%s\", \"%s\", \"%s\", \"%s\", \"%s\", \"%s\", \"%s\", \"%s\", \"%s\"],\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
    }
}'  $STATUS_FILE >> $PHP_FILE
echo "); ?>" >> $PHP_FILE

echo "<html>
<head>
    <title>DmOS Storm-Control Action Shutdown</title>
    <style>
        table {
            border-collapse: collapse;
            width: 100%;
        }
        th, td {
            border: 1px solid black;
            padding: 8px;
            text-align: left;
        }
        th {
            background-color: #f2f2f2;
        }
        .green-text {
            color: green;
        }
        .red-text {
            color: red;
        }
        body {
            font-family: Calibri, sans-serif; /* Definindo a fonte Calibri para o corpo do documento */
        }
    </style>
    <script>
        setInterval(function() {
            location.reload();
        }, 5000); // Refresh every 5 seconds
    </script>
</head>
<body>

<h2>DmOS Storm-Control Action Shutdown</h2>
<table>
    <tr>
        <th>Anel ID</th>
        <th>Name</th>
        <th>Switch IP</th>
        <th>Interface</th>
        <th>Main/Backup</th>
        <th>Admin State</th>
        <th>Oper State</th>
        <th>Broadcast/Multicast</th>
        <th>PPS</th>
        <th>Max PPS</th>
    </tr>
    <?php foreach(\$data as \$row): ?>
    <tr>
        <?php foreach(\$row as \$key => \$cell): ?>
        <?php if (\$key == 5 && \$cell == 'Up') { ?>
            <td class=\"green-text\">
        <?php } elseif (\$key == 5 && \$cell == 'Down') { ?>
            <td class=\"red-text\">
        <?php } elseif (\$key == 6 && \$cell == 'Up') { ?>
            <td class=\"green-text\">
        <?php } elseif (\$key == 6 && \$cell == 'Down') { ?>
            <td class=\"red-text\">
        <?php } elseif (\$key == 8 && \$cell < \$row[9]) { ?>
            <td class=\"green-text\">
        <?php } elseif (\$key == 8 && \$cell > \$row[9]) { ?>
            <td class=\"red-text\">
        <?php } else { ?>
            <td>
        <?php } ?>
        <?php echo \$cell; ?></td>
        <?php endforeach; ?>
    </tr>
    <?php endforeach; ?>
</table>

<div class=\"log-section\">
    <h3>Últimas 100 linhas do Log:</h3>
    <ul>
        <?php
        \$log_file = \"$LOG_FILE\";
        \$lines = array_reverse(file(\$log_file));
        \$count = 0;
        foreach (\$lines as \$line) {
            if (\$count < 100) {
                echo \"<li>\" . htmlspecialchars(\$line) . \"</li>\";
                \$count++;
            } else {
                break;
            }
        }
        ?>
    </ul>
</div>

</body>
</html>" >> $PHP_FILE

#echo "PHP page generated: $PHP_FILE"
}

# Função para verificação dos anéis de acordo com o intervalo definido na configuração
while [ 1 -lt 2 ]; do
   storm_control_action_shutdown
   create_php
   sleep $period
done
