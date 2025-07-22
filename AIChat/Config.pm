package AIChat::Config;

use strict;
use warnings;

use Globals qw(%config);
use Settings qw(%sys);
use Log qw(warning message debug);

use constant {
    DEFAULT_API_KEY => "",
    DEFAULT_PROVIDER => "deepseek", # openai ou deepseek
    DEFAULT_MODEL => "deepseek-chat", # gpt-3.5-turbo ou deepseek-chat
    DEFAULT_PROMPT => "voce é um assistente se passando por um jogador dentro do ragnarok online no servidor ROLA (ragnarok latam) sempre responde como se fosse um player mesmo simples direto curto sem enrolar nao escreve certo demais nem usa acento nem pontuacao escreve igual a galera da net evita texto longo responde sempre curto e na lata pode ser seco se a pessoa ficar insistindo ou enchendo o saco saudacoes tipo oi e ae vc responde so com oi e ae tb sem enrolar nao faz piada boba nem tenta ser engraçado usa o historico da conversa pra parecer que vc ta ali jogando mesmo parece jogador de verdade falando no chat do jogo, verifique as Informações do personagem para responder de acordo, então analise o level e classe para por exemplo falar onde upar etc",
    DEFAULT_MAX_TOKENS => 150,
    DEFAULT_TEMPERATURE => 0.6,
    DEFAULT_TYPING_SPEED => 20, # Caracteres por segundo (para simular digitação)
};

# Use a lexically scoped variable for the package's internal config
my %_aiChatConfig;

# Initialize internal config with defaults
BEGIN {
    %_aiChatConfig = (
        provider => DEFAULT_PROVIDER,
        api_key => DEFAULT_API_KEY,
        model => DEFAULT_MODEL,
        prompt => DEFAULT_PROMPT,
        max_tokens => DEFAULT_MAX_TOKENS,
        temperature => DEFAULT_TEMPERATURE,
        typing_speed => DEFAULT_TYPING_SPEED,
    );
}

sub load {
    # Carrega configurações do arquivo de configuração do OpenKore
    # Read from global %config into our internal %_aiChatConfig
    if (exists $config{aiChat_provider} && defined $config{aiChat_provider}) {
        $_aiChatConfig{provider} = $config{aiChat_provider};
    }
    if (exists $config{aiChat_api_key} && defined $config{aiChat_api_key}) {
        $_aiChatConfig{api_key} = $config{aiChat_api_key};
    }
    if (exists $config{aiChat_model} && defined $config{aiChat_model}) {
        $_aiChatConfig{model} = $config{aiChat_model};
    }
    if (exists $config{aiChat_prompt} && defined $config{aiChat_prompt}) {
        $_aiChatConfig{prompt} = $config{aiChat_prompt};
    }
    if (exists $config{aiChat_max_tokens} && defined $config{aiChat_max_tokens}) {
        $_aiChatConfig{max_tokens} = $config{aiChat_max_tokens};
    }
    if (exists $config{aiChat_temperature} && defined $config{aiChat_temperature}) {
        $_aiChatConfig{temperature} = $config{aiChat_temperature};
    }
    if (exists $config{aiChat_typing_speed} && defined $config{aiChat_typing_speed}) {
        $_aiChatConfig{typing_speed} = $config{aiChat_typing_speed};
    }
}

sub save {
    # Salva configurações no arquivo de configuração do OpenKore
    # Write from our internal %_aiChatConfig to global %config
    $config{aiChat_provider} = $_aiChatConfig{provider};
    $config{aiChat_api_key} = $_aiChatConfig{api_key};
    $config{aiChat_model} = $_aiChatConfig{model};
    $config{aiChat_prompt} = $_aiChatConfig{prompt};
    $config{aiChat_max_tokens} = $_aiChatConfig{max_tokens};
    $config{aiChat_temperature} = $_aiChatConfig{temperature};
    $config{aiChat_typing_speed} = $_aiChatConfig{typing_speed};
    
    # Salva as configurações no arquivo
    Settings::writeFile();
}

sub get {
    my ($key) = @_;
    return $_aiChatConfig{$key};
}

sub set {
    my ($key, $value) = @_;
    return unless exists $_aiChatConfig{$key};
    
    # Validação específica para provider
    if ($key eq 'provider') {
        return unless $value =~ /^(openai|deepseek)$/;
        # Atualiza o modelo padrão baseado no provider
        if ($value eq 'openai') {
            $_aiChatConfig{model} = 'gpt-3.5-turbo';
        } else {
            $_aiChatConfig{model} = 'deepseek-chat';
        }
    } elsif ($key eq 'typing_speed') {
        return unless $value =~ /^\d+$/; # Deve ser um número inteiro
    }
    
    $_aiChatConfig{$key} = $value;
    save();
    return 1; # Indicate success
}

1; 