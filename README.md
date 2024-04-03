# dmos-storm-control-action-shutdown

Este script aplica o comando shutdown na interface Backup de um determinado anel caso o Storm de Broadcast ou Multicast ocorra no anel.
Funcionamento: Como fator de decisão o script compara o PPS de Broadcast Input ou Multicast Input com o limitar configurado no arquivo './dmos-storm-control-action-shutdown.conf' e caso um dos valores seja violado na interface Main ou Backup a interface Backup será colocada em shutdown. As leituras são feitas por SNMPv2 e a configuração de shutdown é realizada por SSH.

Uso: ./dmos-storm-control-action-shutdown.sh -h -t

Opções:
  -h               Exibe ajuda
  -t               Modo teste, o comando shutdown não será aplicado mesmo que os limiares de PPS sejam atingidos (opcional)
  -d               Habilita o modo debug (opcional)

Exemplo de uso (para realizar testes ou debug):
  ./dmos-storm-control-action-shutdown.sh -t -d

Exemplo de uso (para aplicar o shutdown caso necessário):
 ./dmos-storm-control-action-shutdown.sh
############ EXEMPLO DE ARQUIVO DE CONFIGURAÇÃO ############
#Credenciais dos switches (todos campos obrigatórios)
ssh-user:wolf
ssh-password:wolf
ssh-port:22
snmp-v2c-community:public
#Periodo em segundos (s) entre as verificações (leituras SNMP)
period:10

# INSTRUÇÕES:
#  Os parâmentros 'anel-<id>-switch-ip', 'anel-<id>-main' e 'anel-<id>-backup' são obrigatórios.
#  Os parâmetros 'anel-<id>-broadcast-max-pps' , 'anel-<id>-multicast-max-pps' e 'anel-<id>-name' são opcionais.
#  Novos anéis podem ser acrescentados conforme necessidade respeitando a lógica do nome das variáveis conforme exemplos a seguir.

#Anel 1 - cliente ABC
anel-1-name:ABC
anel-1-switch-ip:172.24.17.190
anel-1-main:ten-gigabit-ethernet-1/1/1
anel-1-backup:ten-gigabit-ethernet-1/1/2
anel-1-broadcast-max-pps:10000
anel-1-multicast-max-pps:10000

#Anel 2 - cliente DEF
anel-2-name:DEF
anel-2-switch-ip:172.24.17.190
anel-2-main:ten-gigabit-ethernet-1/1/3
anel-2-backup:ten-gigabit-ethernet-1/1/4
anel-2-broadcast-max-pps:10000
# anel-2-multicast-max-pps:10000 <---- comentar a linha caso não seja desejado desabilitar a verificação

#Anel 3 - cliente GHI
anel-3-name:GHI
anel-3-switch-ip:172.24.17.190
anel-3-main:ten-gigabit-ethernet-1/1/5
anel-3-backup:ten-gigabit-ethernet-1/1/6
anel-3-broadcast-max-pps:10000
anel-3-multicast-max-pps:10000

############ LOGS E STATUS ############
É possível visualizar os logs em um arquivo .log, os status das interfaces em um arquivo CSV e/ou em uma página PHP conforme arquivos informados nas variáveis abaixo contidas no script "dmos-storm-control-action-shutdown.sh", exemplo:

CONFIG_FILE="$SCRIPT_PATH/dmos-storm-control-action-shutdown.conf"
LOG_FILE="$SCRIPT_PATH/dmos-storm-control-action-shutdown.log"
STATUS_FILE="$SCRIPT_PATH/dmos-storm-control-action-shutdown.csv"
PHP_FILE="/var/www/html/dmos-storm-control-action-shutdown.php"

############ INSTALANDO COMO UM SERVIÇO ############
Para instalar o script como um serviço pode-se seguir os seguintes passos:

$ sudo nano /etc/systemd/system/dmos-storm-control.service
"
[Unit]
Description=DMOS Storm Control Service
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=5
User=root
ExecStart=/caminho/para/o/script/dmos-storm-control-action-shutdown.sh 
## (dica de caminho: /opt/dmos-storm-control-action-shutdown/dmos-storm-control-action-shutdown.sh), o script e o arquivo de configuração dmos-storm-control-action-shutdown.conf devem estar no mesmo caminho ###

[Install]
WantedBy=multi-user.target
"

Salve e feche o arquivo.
- Agora, recarregue os serviços do systemd para garantir que ele reconheça o novo serviço:

$ sudo systemctl daemon-reload

- Em seguida, você pode iniciar o serviço:

$ sudo systemctl start dmos-storm-control

- Para garantir que o serviço seja iniciado automaticamente na inicialização do sistema, você pode habilitá-lo:

$ sudo systemctl enable dmos-storm-control

Agora o script dmos-storm-control-action-shutdown.sh será iniciado como um serviço no sistema. Você pode parar, iniciar, reiniciar e verificar o status do serviço usando os comandos systemctl. Por exemplo:

- Para parar o serviço:

$ sudo systemctl stop dmos-storm-control

- Para iniciar o serviço:

$ sudo systemctl start dmos-storm-control

- Para reiniciar o serviço:

$ sudo systemctl restart dmos-storm-control

- Para verificar o status do serviço:

$ sudo systemctl status dmos-storm-control
