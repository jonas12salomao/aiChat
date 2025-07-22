package AIChat::APIClient;

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Request;
use JSON::Tiny qw(decode_json encode_json);
use Log qw(warning message debug);
use Utils qw(dumpHash);

use AIChat::Config;
use AIChat::ConversationHistory;

my $ua = LWP::UserAgent->new;
$ua->timeout(20); # Aumentar timeout para proxy

sub new {
    my $class = shift;
    my $self = {
        provider => AIChat::Config::get('provider'),
        # Não precisamos mais da API Key aqui, o proxy cuidará disso
        # api_key => AIChat::Config::get('api_key'),
        model => AIChat::Config::get('model'),
        max_tokens => AIChat::Config::get('max_tokens'),
        temperature => AIChat::Config::get('temperature'),
    };
    bless $self, $class;
    return $self;
}

sub callAPI {
    my ($self, $message, $sender) = @_;

    my $proxy_url = 'http://localhost:3000/proxy'; # URL do seu servidor Node.js

    # Obtém o histórico de conversas do jogador
    my $history = AIChat::ConversationHistory::getHistory($sender);
    
    # Prepara as mensagens incluindo o histórico
    my @messages = (
        {
            role => "system",
            content => AIChat::Config::get('prompt')
        }
    );
    
    # Adiciona o histórico de conversas, garantindo que mensagens do sistema fiquem no início
    my @system_messages = grep { $_->{role} eq "system" } @$history;
    my @other_messages = grep { $_->{role} ne "system" } @$history;
    
    push @messages, @system_messages;
    push @messages, @other_messages;
    
    # Adiciona a mensagem atual
    push @messages, {
        role => "user",
        content => $message
    };

    my $data = {
        provider => $self->{provider}, # Enviar o provedor para o proxy
        model => $self->{model},
        messages => \@messages,
        max_tokens => $self->{max_tokens},
        temperature => $self->{temperature}
    };

    my $json_data = encode_json($data);

    my $request = HTTP::Request->new('POST', $proxy_url);
    $request->header('Content-Type' => 'application/json');
    # $request->header('Authorization' => 'Bearer ' . $self->{api_key}); # Removido, proxy adiciona
    $request->content($json_data);
    
    my $response = $ua->request($request);
    

    if ($response->is_success) {
        my $result = decode_json($response->content);
        # A resposta do proxy já deve ser o conteúdo direto da API de IA
        return $result->{choices}[0]{message}{content};
    } else {
        warning "[aiChat] Proxy request failed: " . $response->status_line . ". Content: " . $response->decoded_content . "\n", "plugin";
        return undef;
    }
}

# Deixamos as subs originais comentadas para referência
sub _sendOpenAIRequest { die "Not implemented, use proxy."; }
sub _sendDeepSeekRequest { die "Not implemented, use proxy."; }

1; 