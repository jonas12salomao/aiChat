package AIChat::APIClient;

use strict;
use warnings;

# Substituindo módulos problemáticos por implementação nativa
# use LWP::UserAgent;
# use HTTP::Request;
# use JSON::Tiny qw(decode_json encode_json);
use Log qw(warning message debug);
use Utils qw(dumpHash);

use AIChat::Config;
use AIChat::ConversationHistory;

# Implementação nativa de JSON
sub encode_json {
    my ($data) = @_;
    
    if (ref($data) eq 'HASH') {
        my @pairs;
        foreach my $key (sort keys %$data) {
            my $value = $data->{$key};
            my $encoded_key = _encode_json_string($key);
            my $encoded_value = _encode_json_value($value);
            push @pairs, "$encoded_key:$encoded_value";
        }
        return '{' . join(',', @pairs) . '}';
    } 
    elsif (ref($data) eq 'ARRAY') {
        my @items;
        foreach my $item (@$data) {
            push @items, _encode_json_value($item);
        }
        return '[' . join(',', @items) . ']';
    }
    else {
        return _encode_json_value($data);
    }
}

sub _encode_json_value {
    my ($value) = @_;
    
    if (not defined $value) {
        return 'null';
    }
    elsif (ref($value) eq 'HASH' || ref($value) eq 'ARRAY') {
        return encode_json($value);
    }
    elsif ($value =~ /^-?\d+(?:\.\d+)?$/ && $value !~ /^0\d+/) {
        return $value; # número
    }
    else {
        return _encode_json_string($value);
    }
}

sub _encode_json_string {
    my ($str) = @_;
    $str =~ s/([\\"\/\b\f\n\r\t])/\\$1/g;
    return '"' . $str . '"';
}

sub decode_json {
    my ($json) = @_;
    
    # Implementação simples para extrair apenas o conteúdo da mensagem que precisamos
    if ($json =~ /"content"\s*:\s*"((?:\\.|[^"\\])*)"/) {
        my $content = $1;
        $content =~ s/\\"/"/g; # Corrige aspas escapadas
        $content =~ s/\\\\/\\/g; # Corrige barras invertidas escapadas
        return { choices => [ { message => { content => $content } } ] };
    }
    
    # Retorno padrão em caso de falha
    return { error => "Falha ao decodificar JSON" };
}

# Cliente HTTP usando sockets
sub http_request {
    my ($method, $url, $headers, $content) = @_;
    
    # Parse a URL
    my ($host, $path) = $url =~ m|http://([^/]+)(/.*)|;
    unless (defined $host && defined $path) {
        return { is_success => 0, status_line => "URL inválida", content => "" };
    }
    
    # Cria o socket
    use IO::Socket::INET;
    my $socket = IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => 3000,
        Proto    => 'tcp',
        Timeout  => 20
    );
    
    unless ($socket) {
        return { is_success => 0, status_line => "Falha ao conectar: $!", content => "" };
    }
    
    # Prepara o request HTTP
    my $request = "$method $path HTTP/1.1\r\n";
    $request .= "Host: $host\r\n";
    $request .= "Content-Length: " . length($content) . "\r\n";
    
    # Adiciona headers
    foreach my $name (keys %$headers) {
        $request .= "$name: " . $headers->{$name} . "\r\n";
    }
    
    # Finaliza headers e adiciona conteúdo
    $request .= "\r\n";
    $request .= $content if defined $content;
    
    # Envia request
    print $socket $request;
    
    # Lê a resposta
    my $response = '';
    my $buffer;
    while (sysread($socket, $buffer, 1024)) {
        $response .= $buffer;
    }
    close $socket;
    
    # Extrai status e conteúdo
    my ($status_line, $rest) = split /\r\n/, $response, 2;
    my ($http_version, $status_code, $reason) = $status_line =~ m|HTTP/(\d\.\d)\s+(\d+)\s+(.*)|;
    
    my ($headers_text, $response_content) = split /\r\n\r\n/, $rest, 2;
    
    return {
        is_success => ($status_code == 200),
        status_line => "$status_code $reason",
        content => $response_content,
        decoded_content => $response_content
    };
}

# Construtor igual ao original
sub new {
    my $class = shift;
    my $self = {
        provider => AIChat::Config::get('provider'),
        # api_key não é mais necessário, o proxy cuida disso
        model => AIChat::Config::get('model'),
        max_tokens => AIChat::Config::get('max_tokens'),
        temperature => AIChat::Config::get('temperature'),
    };
    bless $self, $class;
    return $self;
}


sub callAPI {
    my ($self, $message, $sender, $custom_prompt) = @_;

    my $proxy_url = 'http://localhost:3000/proxy'; # URL do servidor Node.js

    # Obtém o histórico de conversas do jogador
    my $history = AIChat::ConversationHistory::getHistory($sender);
    
    # Prepara as mensagens incluindo o histórico 
    # Adicionado um custom_prompt no método para permitir customização de prompts
    my @messages = (
        {
            role => "system",
            content => defined($custom_prompt) ? $custom_prompt : AIChat::Config::get('prompt')
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
    
    # Usa nossa versão nativa de HTTP ao invés de LWP::UserAgent
    my $headers = {
        'Content-Type' => 'application/json'
    };
    
    my $response = http_request('POST', $proxy_url, $headers, $json_data);
    
    if ($response->{is_success}) {
        my $result = decode_json($response->{content});
        # A resposta do proxy já deve ser o conteúdo direto da API de IA
        return $result->{choices}[0]{message}{content};
    } else {
        warning "[aiChat] Proxy request failed: " . $response->{status_line} . ". Content: " . $response->{decoded_content} . "\n", "plugin";
        return undef;
    }
}


# Implementação de callAPI idêntica ao original
sub callAPIOld {
    my ($self, $message, $sender) = @_;

    my $proxy_url = 'http://localhost:3000/proxy'; # URL do servidor Node.js

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
    
    # Usa nossa versão nativa de HTTP ao invés de LWP::UserAgent
    my $headers = {
        'Content-Type' => 'application/json'
    };
    
    my $response = http_request('POST', $proxy_url, $headers, $json_data);
    
    if ($response->{is_success}) {
        my $result = decode_json($response->{content});
        # A resposta do proxy já deve ser o conteúdo direto da API de IA
        return $result->{choices}[0]{message}{content};
    } else {
        warning "[aiChat] Proxy request failed: " . $response->{status_line} . ". Content: " . $response->{decoded_content} . "\n", "plugin";
        return undef;
    }
}

# Mantém as mesmas subs originais comentadas para referência
sub _sendOpenAIRequest { die "Not implemented, use proxy."; }
sub _sendDeepSeekRequest { die "Not implemented, use proxy."; }

1; 