package AIChat::MessageHandler;

use strict;
use warnings;

use Log qw(warning message debug error);
# No direct Globals qw($char %jobs_lut $field) here.
# Instead, we will rely on data populated by aiChat.pl

use AIChat::APIClient;
use AIChat::Config;
use AIChat::ConversationHistory;

# Global hash to store the bot's character data
our %bot_character_data;

my $api_client;

BEGIN {
    $api_client = AIChat::APIClient->new();
}

sub getCharacterInfo {
    my ($sender) = @_;
    
    # Checks if character data is available
    return undef unless %bot_character_data;

    # Checks if there's an existing conversation history for this player
    # If yes, we don't add the system message again for this specific type of info.
    my $history = AIChat::ConversationHistory::getHistory($sender);
    # Check if a 'system' message with 'character_info' type already exists
    my $system_info_exists = 0;
    for my $msg_ref (@$history) {
        if ($msg_ref->{role} eq "system" && $msg_ref->{type} && $msg_ref->{type} eq "character_info") {
            $system_info_exists = 1;
            last;
        }
    }
    return undef if $system_info_exists;

    # Format the message with the bot's character information
    my $info = sprintf(
        "Informações do personagem que voce está simulando:\n" .
        "Nome: %s\n" .
        "Classe: %s\n" .
        "Level Base: %d\n" .
        "Level Job: %d\n" .
        "Mapa Atual: %s",
        $bot_character_data{name},
        $bot_character_data{job},
        $bot_character_data{base_level},
        $bot_character_data{job_level},
        $bot_character_data{map_name}
    );
    
    return $info;
}

sub processMessage {
    my ($message, $sender, $custom_prompt) = @_;

    # Adicionado custom_prompt 

    # Check if it's the first message and add character info
    my $char_info = getCharacterInfo($sender);
    if ($char_info) {
        AIChat::ConversationHistory::addMessage($sender, "system", $char_info, "character_info");
    }

    # Adiciona a mensagem do usuário ao histórico
    AIChat::ConversationHistory::addMessage($sender, "user", $message);

    my $response;
    eval {
        $response = $api_client->callAPI($message, $sender, $custom_prompt);
    };
    if ($@) {
        error "[aiChat] Erro ao chamar a API: $@\n", "plugin";
        return undef;
    }
    
    if (defined $response && length $response > 0) {
        # Adiciona a resposta da IA ao histórico
        AIChat::ConversationHistory::addMessage($sender, "assistant", $response);
        return $response;
    } else {
        return undef;
    }
}


sub processMessageOld {
    my ($message, $sender) = @_;

    # Check if it's the first message and add character info
    my $char_info = getCharacterInfo($sender);
    if ($char_info) {
        AIChat::ConversationHistory::addMessage($sender, "system", $char_info, "character_info");
    }

    # Adiciona a mensagem do usuário ao histórico
    AIChat::ConversationHistory::addMessage($sender, "user", $message);

    my $response;
    eval {
        $response = $api_client->callAPI($message, $sender);
    };
    if ($@) {
        error "[aiChat] Erro ao chamar a API: $@\n", "plugin";
        return undef;
    }
    
    if (defined $response && length $response > 0) {
        # Adiciona a resposta da IA ao histórico
        AIChat::ConversationHistory::addMessage($sender, "assistant", $response);
        return $response;
    } else {
        return undef;
    }
}

1; 