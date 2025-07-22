package AIChat::ConversationHistory;

use strict;
use warnings;

use Log qw(warning message debug);

# Hash para armazenar o histórico de conversas por jogador
my %conversation_history;

# Número máximo de mensagens a manter no histórico por jogador
use constant MAX_HISTORY => 10;

sub addMessage {
    my ($player, $role, $content) = @_;
    
    # Inicializa o histórico do jogador se não existir
    if (!exists $conversation_history{$player}) {
        $conversation_history{$player} = [];
    }
    
    # Adiciona a nova mensagem
    push @{$conversation_history{$player}}, {
        role => $role,
        content => $content
    };
    
    # Mantém apenas as últimas MAX_HISTORY mensagens
    if (scalar @{$conversation_history{$player}} > MAX_HISTORY) {
        shift @{$conversation_history{$player}};
    }
}

sub getHistory {
    my ($player) = @_;
    
    # Retorna o histórico do jogador ou array vazio se não existir
    return exists $conversation_history{$player} ? $conversation_history{$player} : [];
}

sub clearHistory {
    my ($player) = @_;
    
    if (exists $conversation_history{$player}) {
        delete $conversation_history{$player};
    }
}

1; 