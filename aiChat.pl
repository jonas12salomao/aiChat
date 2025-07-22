package aiChat;

use strict;
use warnings;

use Commands;
use Globals qw(%timeout $messageSender $net %config $char $field %jobs_lut);
use Settings qw(%sys);
use I18N qw(bytesToString);
use Log qw(warning message debug);
use Plugins;
use Utils qw(getHex timeOut getFormattedDate);
use Cwd 'abs_path';
use Time::HiRes qw(sleep);
use Misc;

use lib $Plugins::current_plugin_folder;
use AIChat::Config;
use AIChat::APIClient;
use AIChat::MessageHandler;
use AIChat::HookManager;

use constant {
    PLUGIN_PREFIX => "[aiChat]",
    PLUGIN_NAME   => "aiChat",
    PLUGIN_PODIR  => "$Plugins::current_plugin_folder/po",

    COMMAND_HANDLE => "aichat",
};

my $translator   = new Translation(PLUGIN_PODIR, $sys{locale});
my $main_command;

# ---------------------------------------------------------------------
# HOOKS
# ---------------------------------------------------------------------
my %hooks = (
    init        => new AIChat::HookManager("start3",                          \&onInitialized),
    in_game     => new AIChat::HookManager("in_game",                          \&updateBotCharacterData),
    map_changed => new AIChat::HookManager("Network::Receive::map_changed",    \&updateBotCharacterData),
);

Plugins::register(PLUGIN_NAME, $translator->translate("AI Chat Integration for OpenKore"), \&onUnload, \&onReload);
$hooks{init}->hook();
$hooks{in_game}->hook();
$hooks{map_changed}->hook();

# -- PM ----------------------------------------------------------------------------------------------------------------
my $privMsgHookID = Plugins::addHook('packet_privMsg', \&onPrivateMessage, undef);
$hooks{packet_privMsg_direct} = $privMsgHookID;

# -- PUBLIC CHAT --------------------------------------------------------------------------------------------------------
my $pubMsgHookID  = Plugins::addHook('packet_pubMsg',  \&onPublicMessage,  undef);
$hooks{packet_pubMsg_direct} = $pubMsgHookID;

# ---------------------------------------------------------------------
# FUNÇÕES AUXILIARES
# ---------------------------------------------------------------------
sub updateBotCharacterData {
    debug "[aiChat] Executando updateBotCharacterData...\n", "plugin";
    if (defined $char && defined $char->{name}) {
        $AIChat::MessageHandler::bot_character_data{name}        = $char->{name}      || 'Desconhecido';
        $AIChat::MessageHandler::bot_character_data{base_level} = $char->{lv}        || 0;
        $AIChat::MessageHandler::bot_character_data{job_level}  = $char->{lv_job}    || 0;
        $AIChat::MessageHandler::bot_character_data{job}        = ($char->{jobID} && $jobs_lut{$char->{jobID}}) || 'Desconhecido';
        my $current_map_name = defined $field ? ($field->baseName || 'Desconhecido') : 'Desconhecido';
        $AIChat::MessageHandler::bot_character_data{map_name}   = $current_map_name;
        debug "[aiChat] Dados do personagem atualizados: " . join(', ', map { "$_: " . $AIChat::MessageHandler::bot_character_data{$_} } keys %AIChat::MessageHandler::bot_character_data) . "\n", 'plugin';
    }
}

# ---------------------------------------------------------------------
# EVENTOS PRINCIPAIS
# ---------------------------------------------------------------------
sub onInitialized {
    Commands::register([
        COMMAND_HANDLE,
        $translator->translate("AI Chat commands"),
        \&onCommand
    ]);
    AIChat::Config::load();
    updateBotCharacterData();
}

sub onUnload {
    Commands::unregister([COMMAND_HANDLE]);
    $_->unhook() for ($hooks{init}, $hooks{in_game}, $hooks{map_changed});
    Plugins::delHook($_) for grep { defined } @hooks{qw/packet_privMsg_direct packet_pubMsg_direct/};
}

sub onReload {
    AIChat::Config::load();
    updateBotCharacterData();
}

# ---------------------------------------------------------------------
# COMANDO DE CONSOLE
# ---------------------------------------------------------------------
sub onCommand {
    my (undef, $args) = @_;
    my $arg = $args // '';

    if ($arg eq 'help') {
        message $translator->translate("Comandos do AI Chat:\n" .
            "aichat help - Mostra esta ajuda\n" .
            "aichat status - Mostra o status atual\n" .
            "aichat config - Mostra a configuração atual\n" .
            "aichat set <chave> <valor> - Define um valor de configuração\n" .
            "aichat provider <openai|deepseek> - Altera o provedor de IA\n"), 'list';

    } elsif ($arg eq 'status') {
        message sprintf("%s Status: Ativo\n", PLUGIN_PREFIX), 'list';
        message "Provedor: "         . AIChat::Config::get('provider'),      'list';
        message "Modelo: "           . AIChat::Config::get('model'),         'list';
        message "Nome: "             . $AIChat::MessageHandler::bot_character_data{name},      'list';
        message "Level Base: "       . $AIChat::MessageHandler::bot_character_data{base_level}, 'list';
        message "Level Job: "        . $AIChat::MessageHandler::bot_character_data{job_level},  'list';
        message "Classe: "           . $AIChat::MessageHandler::bot_character_data{job},        'list';
        message "Mapa: "             . $AIChat::MessageHandler::bot_character_data{map_name},   'list';

    } elsif ($arg eq 'config') {
        message sprintf("%s Configuração:\n", PLUGIN_PREFIX), 'list';
        for my $key (qw/provider api_key model prompt max_tokens temperature typing_speed GM_prompt/) {
            my $val = AIChat::Config::get($key);
            $val = ($key eq 'api_key') ? ($val ? 'Configurada' : 'Não configurada') : $val;
            message "$key: $val", 'list';
        }

    } elsif ($arg =~ /^provider\s+(openai|deepseek)$/) {
        my $ok = AIChat::Config::set('provider', $1);
        message sprintf("%s Provedor alterado para %s\n", PLUGIN_PREFIX, $1), 'list' if $ok;

    } elsif ($arg =~ /^set\s+(\w+)\s+(.+)$/) {
        my ($k,$v) = ($1,$2);
        my $ok = AIChat::Config::set($k,$v);
        message ($ok ? sprintf("%s Configuração atualizada.\n",PLUGIN_PREFIX) : 'Chave de configuração inválida.'), 'list';

    } else {
        message 'Comando desconhecido. Use "aichat help" para ver os comandos disponíveis.', 'list';
    }
}

# ---------------------------------------------------------------------
# MENSAGENS PRIVADAS
# ---------------------------------------------------------------------
sub onPrivateMessage {
    my (undef, $args) = @_;
    my $sender  = bytesToString($args->{privMsgUser});
    my $message = bytesToString($args->{privMsg});

    Misc::chatLog('pm', "(From: $sender) : $message\n") if $config{logPrivateChat};
    _append_to_log("(From: $sender) : $message");

    my $response = AIChat::MessageHandler::processMessage($message, $sender);
    _send_response_pm($sender, $response) if defined $response && length $response;
}

# ---------------------------------------------------------------------
# MENSAGENS PÚBLICAS
# ---------------------------------------------------------------------
sub onPublicMessage {
    my (undef, $args) = @_;
    my $sender  = bytesToString($args->{pubMsgUser});
    my $message = bytesToString($args->{pubMsg});

    if (defined $field && defined $config{saveMap} && $field->baseName eq $config{saveMap}) {
        debug sprintf('[aiChat] Ignorando mensagem pública em saveMap "%s".\n', $field->baseName), 'plugin';
        return;
    }

    return unless _is_gm_message($message);

    Misc::chatLog('c', "(Possível GM $sender): $message\n") if $config{logPublicChat};

    Commands::run('conf sitAuto_idle 0');
    Commands::run('conf route_randomWalk 0');
    Commands::run('conf lockMap none');
    Commands::run('conf attackAuto 0');

    my $response = AIChat::MessageHandler::processMessage($message, $sender, AIChat::Config::get('GM_prompt'));
    _send_response_public($response) if defined $response && length $response;
}

# ---------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------
sub _send_response_pm {
    my ($to,$text) = @_;
    return unless defined $text;
    _simulate_typing($text);
    $messageSender->sendPrivateMsg($to, $text);
    Misc::chatLog('pm', "(To: $to) : $text\n") if $config{logPrivateChat};
    _append_to_log("(To: $to) : $text");
}

sub _send_response_public {
    my ($text) = @_;
    _simulate_typing($text);
    $messageSender->sendChat($text);
    Misc::chatLog('c', "(To Public): $text\n") if $config{logPublicChat};
    _append_to_log("(To Public): $text");
}

sub _simulate_typing {
    my ($text) = @_;
    my $speed = AIChat::Config::get('typing_speed');
    return unless $speed && $speed > 0;
    my $delay = length($text)/$speed;
    message sprintf('[aiChat] Simulando digitação por %.2f segundos.\n',$delay), 'debug';
    sleep $delay;
}

sub _append_to_log {
    my ($line) = @_;
    open my $fh, '>>', 'logs/aiChat_respostas.txt' or return;
    print $fh '['.getFormattedDate(time).'] '.$line."\n";
    close $fh;
}

# ---------------------------------------------------------------------
# DETECÇÃO DE GM
# ---------------------------------------------------------------------
sub _is_gm_message {
    my ($msg) = @_;
    $msg = lc($msg // '');
    $msg =~ s/[^a-z0-9\sáéíóúãõâêîôûç]//g;

    my @patterns = (
    qr/\baqui\s+.*gm\b/,                      # “aqui ... GM”  (Ex.: “Oi, aqui é o GM Tachius”)
    qr/\bsou\s+.*gm\b/,                       # “sou ... GM”   (Ex.: “Eu sou o GM Alokss”)
    qr/\bol[aã],?\s+aqui\s+.*gm/,             # “olá, aqui ... GM” (variação com saudação)
    qr/\bresponda\b/,                         # palavra “responda” (ordem direta)
    qr/entender[ei]?\s+que\s+é?\s+um\s+bot/,  # trecho “entender(ei) que (é) um bot”
    qr/conta\s+ser[áa]\s+(bloqueada|bloqueado|banida|banido)/, # “conta será bloqueada/banida”
    qr/\b(?:bloquead[oa])\b/,                 # palavra isolada “bloqueado” ou “bloqueada”
    qr/\b(?:gm)\b/,                           # palavra isolada “GM”
    qr/última\s+chance/,                      # expressão “última chance”
    qr/\bpuni[çc][ãa]o\b/,                    # “punição” / “punicao” (singular)
    qr/\bpuni[çc][õo]es\b/,                   # “punições” / “punicoes” (plural)
    qr/\bbot\b/,                              # palavra isolada “bot”
    qr/\b(10|9|8|7|6|5|4|3|2|1|0)\b/,         # números 10‒0 (contagem regressiva)
	);


    foreach my $re (@patterns) {
        return 1 if $msg =~ $re;
    }
    return 0;
}


1;
