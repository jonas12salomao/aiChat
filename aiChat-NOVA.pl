###########################################################################
############################# aiChat ######################################
#################### --- Não foi eu que fiz --- ###########################
################ --- adicionei apenas o pubmsg --- ########################
################ --- para responder no sec_pri --- ########################
############ Chave Pix: ed23b7e1-8986-4f63-ab13-0d37928082dd ##############
###########################################################################

package aiChat;

use strict;
use warnings;

use Commands;
use Globals qw(%timeout $messageSender $net %config $char $field %jobs_lut);
use Settings qw(%sys);
use I18N qw(bytesToString);
use Log qw(warning message debug);
use Plugins;
use Utils qw(getHex timeOut);
use Cwd 'abs_path';
use Time::HiRes qw(sleep);

use lib $Plugins::current_plugin_folder;
use AIChat::Config;
use AIChat::APIClient;
use AIChat::MessageHandler;
use AIChat::HookManager;

use constant {
    PLUGIN_PREFIX => "[aiChat]",
    PLUGIN_NAME => "aiChat",
    PLUGIN_PODIR => "$Plugins::current_plugin_folder/po",
    
    COMMAND_HANDLE => "aichat",
};

my $translator = new Translation(PLUGIN_PODIR, $sys{locale});
my $main_command;

my %hooks = (
    init => new AIChat::HookManager("start3", \&onInitialized),
    in_game => new AIChat::HookManager("in_game", \&updateBotCharacterData),
    map_changed => new AIChat::HookManager("Network::Receive::map_changed", \&updateBotCharacterData),
);

Plugins::register(PLUGIN_NAME, $translator->translate("AI Chat Integration for OpenKore"), \&onUnload, \&onReload);
$hooks{init}->hook();
$hooks{in_game}->hook();
$hooks{map_changed}->hook();

# Registrar o hook de mensagens privadas diretamente para debug
my $privMsgHookID = Plugins::addHook('packet_privMsg', \&onPrivateMessage, undef);
my $pubMsgHookID = Plugins::addHook('packet_pubMsg', \&onPubMessage, undef);
# Armazenar o ID para desregistrar depois
$hooks{packet_privMsg_direct} = $privMsgHookID;
$hooks{packet_pubMsg_direct} = $pubMsgHookID;


sub updateBotCharacterData {
    # Popula AIChat::MessageHandler::%bot_character_data com as informações mais recentes do personagem
    debug "[aiChat] Executando updateBotCharacterData...\n", "plugin";
    if (defined $char && defined $char->{name}) {
        $AIChat::MessageHandler::bot_character_data{name} = $char->{name} || "Desconhecido";
        $AIChat::MessageHandler::bot_character_data{base_level} = $char->{lv} || 0;
        $AIChat::MessageHandler::bot_character_data{job_level} = $char->{lv_job} || 0;
        $AIChat::MessageHandler::bot_character_data{job} = ($char->{jobID} && $jobs_lut{$char->{jobID}}) || "Desconhecido";
        
        my $current_map_name = "Desconhecido";
        if (defined $field) {
            $current_map_name = $field->baseName || "Desconhecido";
            debug "[aiChat] \$field está definido. baseName: '$current_map_name'\n", "plugin";
        } else {
            debug "[aiChat] \$field não está definido.\n", "plugin";
        }
        $AIChat::MessageHandler::bot_character_data{map_name} = $current_map_name;
        
        debug "[aiChat] Dados do personagem atualizados: " . join(", ", map { "$_: " . $AIChat::MessageHandler::bot_character_data{$_} } keys %AIChat::MessageHandler::bot_character_data) . "\n", "plugin";
    } else {
        debug "[aiChat] Não foi possível atualizar os dados do personagem: \$char ou \$char->{name} não definidos.\n", "plugin";
    }
}

sub onInitialized {
    Commands::register([
        COMMAND_HANDLE,
        $translator->translate("AI Chat commands"),
        \&onCommand
    ]);
    AIChat::Config::load();

    # Chamar updateBotCharacterData uma vez na inicialização, caso o bot já esteja em jogo
    updateBotCharacterData();
}

sub onUnload {
    Commands::unregister([COMMAND_HANDLE]);
    # Desativar o hook de inicialização e o hook de mensagens privadas direto
    $hooks{init}->unhook();
    $hooks{in_game}->unhook();
    $hooks{map_changed}->unhook();
    Plugins::delHook($hooks{packet_privMsg_direct}) if defined $hooks{packet_privMsg_direct};
    Plugins::delHook($hooks{packet_pubMsg_direct}) if defined $hooks{packet_pubMsg_direct};
    
    
    # Tentar encerrar o servidor Node.js
    my $pid_file = "plugins/aiChat/proxy_pid.txt";
    if (-e $pid_file) { # Se o arquivo PID existe
        open my $fh, '<', $pid_file or warning "[aiChat] Não foi possível abrir $pid_file: $!\n", "plugin";
        my $pid = <$fh>;
        chomp $pid;
        close $fh;

        if ($pid =~ /^\d+$/) {
            system("taskkill /F /PID $pid"); # /F para forçar o encerramento
        } else {
            warning "[aiChat] PID inválido encontrado em $pid_file: '$pid'\n", "plugin";
        }
        unlink $pid_file or warning "[aiChat] Não foi possível remover $pid_file: $!\n", "plugin";
    } else {
        debug "[aiChat] Arquivo PID ($pid_file) não encontrado. O proxy pode já ter sido fechado ou não foi iniciado.\n", "plugin";
    }
}

sub onReload {
    AIChat::Config::load();
    updateBotCharacterData(); # Atualizar dados ao recarregar
}

sub onCommand {
    my (undef, $args) = @_;
    my $arg = $args;
    
    if ($arg eq "help") {
        message $translator->translate("Comandos do AI Chat:\n" .
            "aichat help - Mostra esta ajuda\n" .
            "aichat status - Mostra o status atual\n" .
            "aichat config - Mostra a configuração atual\n" .
            "aichat set <chave> <valor> - Define um valor de configuração\n" .
            "aichat provider <openai|deepseek> - Altera o provedor de IA\n"), "list";
    } elsif ($arg eq "status") {
        message $translator->translatef("%s Status: Ativo\n", PLUGIN_PREFIX), "list";
        message "Provedor: " . AIChat::Config::get('provider'), "list";
        message "Modelo: " . AIChat::Config::get('model'), "list";
        message "Nome: " . $AIChat::MessageHandler::bot_character_data{name}, "list";
        message "Level Base: " . $AIChat::MessageHandler::bot_character_data{base_level}, "list";
        message "Level Job: " . $AIChat::MessageHandler::bot_character_data{job_level}, "list";
        message "Classe: " . $AIChat::MessageHandler::bot_character_data{job}, "list";
        message "Mapa: " . $AIChat::MessageHandler::bot_character_data{map_name}, "list";
    } elsif ($arg eq "config") {
        message $translator->translatef("%s Configuração:\n", PLUGIN_PREFIX), "list";
        message "Provedor: " . AIChat::Config::get('provider'), "list";
        message "Chave API: " . (AIChat::Config::get('api_key') ? "Configurada" : "Não configurada"), "list";
        message "Modelo: " . AIChat::Config::get('model'), "list";
        message "Prompt: " . AIChat::Config::get('prompt'), "list";
        message "Max Tokens: " . AIChat::Config::get('max_tokens'), "list";
        message "Temperatura: " . AIChat::Config::get('temperature'), "list";
    } elsif ($arg =~ /^provider\s+(openai|deepseek)$/) {
        if (AIChat::Config::set('provider', $1)) {
            message $translator->translatef("%s Provedor alterado para %s\n", PLUGIN_PREFIX, $1), "list";
        } else {
            message $translator->translate("Provedor inválido. Use 'openai' ou 'deepseek'."), "list";
        }
    } elsif ($arg =~ /^set\s+(\w+)\s+(.+)$/) {
        my ($key, $value) = ($1, $2);
        if (AIChat::Config::set($key, $value)) {
            message $translator->translatef("%s Configuração atualizada.\n", PLUGIN_PREFIX), "list";
        } else {
            message $translator->translate("Chave de configuração inválida."), "list";
        }
    } else {
        message $translator->translate("Comando desconhecido. Use 'aichat help' para ver os comandos disponíveis."), "list";
    }
}


# Armazena contadores e timestamps por sender
my %response_tracker;

sub onPrivateMessage {
    my (undef, $args) = @_;
    my $sender = bytesToString($args->{privMsgUser});
    my $message = bytesToString($args->{privMsg});
    my $now = time;

    my $window_seconds = 20 * 60; # 20 minutos
    my $max_responses = 3;

    # Inicializa o rastreamento, se necessário
    if (!exists $response_tracker{$sender}) {
        $response_tracker{$sender} = {
            count => 0,
            start_time => $now
        };
    }

    # Verifica se a janela de 20 minutos já passou
    if ($now - $response_tracker{$sender}->{start_time} > $window_seconds) {
        $response_tracker{$sender}->{count} = 0;
        $response_tracker{$sender}->{start_time} = $now;
    }

    # Verifica se excedeu o limite de respostas
    if ($response_tracker{$sender}->{count} >= $max_responses) {
        debug "[aiChat] '$sender' excedeu o limite de $max_responses respostas por 20 minutos.\n", "plugin";
        return;
    }

    # Processa a mensagem e obtém a resposta da IA
    my $response = AIChat::MessageHandler::processMessage($message, $sender);

    if ($response) {
        my $typing_speed = AIChat::Config::get('typing_speed');
        if ($typing_speed > 0) {
            my $delay = length($response) / $typing_speed;
            message "[aiChat] Simulando digitação por $delay segundos...\n", "debug";
            sleep($delay);
        }

        $messageSender->sendPrivateMsg($sender, $response);

        # Incrementa o contador de respostas
        $response_tracker{$sender}->{count}++;
    } else {
        debug "[aiChat] Nenhuma resposta da AI gerada para '$message'\n", "plugin";
    }
}



sub onPrivateMessageOld {
    my (undef, $args) = @_;
    my $sender = bytesToString($args->{privMsgUser});
    my $message = bytesToString($args->{privMsg});
    
    # Process message and get AI response
    my $response = AIChat::MessageHandler::processMessage($message, $sender);
    
    if ($response) {
        my $typing_speed = AIChat::Config::get('typing_speed');
        if ($typing_speed > 0) {
            my $delay = length($response) / $typing_speed;
            message "[aiChat] Simulando digitação por $delay segundos...\n", "debug";
            sleep($delay);
        }
        
        $messageSender->sendPrivateMsg($sender, $response);
    } else {
        debug "[aiChat] Nenhuma resposta da AI gerada para '$message'\n", "plugin";
    }
}

sub onPubMessage {
    my (undef, $args) = @_;
    my $sender = bytesToString($args->{pubMsgUser});
    my $message = bytesToString($args->{pubMsg});

    my $mapa_atual = $AIChat::MessageHandler::bot_character_data{map_name};

    if (length($message) <= 1) {
         debug "[aiChat] Não faça nada se for uma contagem ou uma mensagem com apenas 1 caracter";
         return;
    }

    if ($mapa_atual !~ "sec_pri") {
        message "[aiChat] estamos no mapa $mapa_atual \n", "debug";
    } else {
        # Define prompt customizado para o mapa "sec_pri"
        my $gm_prompt = AIChat::Config::get('gm_prompt');

        # Processa a mensagem com prompt customizado
        my $response = AIChat::MessageHandler::processMessage($message, $sender, $gm_prompt);

        if ($response) {
            my $typing_speed = AIChat::Config::get('typing_speed');
            if ($typing_speed > 0) {
                my $delay = length($response) / $typing_speed;
                message "[aiChat] Simulando digitação por $delay segundos...\n", "debug";
                message "[aiChat] estamos no mapa $mapa_atual \n", "debug";
                sleep($delay);
            }

            $messageSender->sendChat($response);
        } else {
            debug "[aiChat] Nenhuma resposta da AI gerada para '$message'\n", "plugin";
        }
    }
}

sub onPubMessageOld {
    my (undef, $args) = @_;
    my $sender = bytesToString($args->{pubMsgUser});
    my $message = bytesToString($args->{pubMsg});

    my $mapa_atual = $AIChat::MessageHandler::bot_character_data{map_name};  # <-- ADICIONADO 'my'

    if ($mapa_atual !~ "sec_pri") {
        message "[aiChat] estamos no mapa $mapa_atual \n", "debug";
    } else {
        # Process message and get AI response
        my $response = AIChat::MessageHandler::processMessage($message, $sender);
        
        if ($response) {
            my $typing_speed = AIChat::Config::get('typing_speed');
            if ($typing_speed > 0) {
                my $delay = length($response) / $typing_speed;
                message "[aiChat] Simulando digitação por $delay segundos...\n", "debug";
                message "[aiChat] estamos no mapa $mapa_atual \n", "debug";
                sleep($delay);
            }
            
            $messageSender->sendChat($response);
        } else {
            debug "[aiChat] Nenhuma resposta da AI gerada para '$message'\n", "plugin";
        }
    }
}

1; 