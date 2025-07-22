# Plugin AI Chat para OpenKore

Este plugin integra o OpenKore com modelos de Linguagem de IA, permitindo que seu bot converse naturalmente com outros jogadores, mantendo o contexto e utilizando informações do seu personagem (nome, classe, níveis, mapa).

## 1. Pré-requisitos e Instalação

Para usar o plugin, você precisará:

*   **OpenKore**: Versão atual.
*   **Node.js**: V16.x+ ([nodejs.org](https://nodejs.org/)).
*   **Módulos Perl (CPAN)**: Instale no terminal do OpenKore ou via `cpan`:
    ```bash
    cpan install LWP::UserAgent HTTP::Request JSON::Tiny
    ```
*   **Pacotes Node.js**: Na pasta `plugins/aiChat`, execute:
    ```bash
    npm install express node-fetch
    ```

1.  Copie a pasta `aiChat` para `openkore/plugins/`.
2.  Instale todos os pré-requisitos acima.

## 2. Configuração

### A. No OpenKore (`config.txt` ou comandos `aichat set`)

Configure as opções no `control/config.txt` ou via console do OpenKore (`aichat set <chave> <valor>`):

*   `aiChat_provider`: `openai` ou `deepseek` (padrão: `deepseek`)
*   `aiChat_model`: `gpt-3.5-turbo` ou `deepseek-chat` (ajustado ao `provider`)
*   `aiChat_prompt`: O prompt que define o comportamento da IA.
*   `aiChat_max_tokens`: Máx. tokens na resposta (padrão: `150`)
*   `aiChat_temperature`: Criatividade da IA (0.0-1.0, padrão: `0.6`)
*   `aiChat_typing_speed`: Velocidade de digitação em caracteres/segundo (padrão: `20`)

### B. No Proxy Node.js (`api_proxy.js`)

Abra `plugins/aiChat/api_proxy.js` e **insira sua chave de API diretamente** (ex: `const DEEPSEEK_API_KEY = 'SUA_CHAVE_AQUI';`).

## 3. Uso

1.  **Inicie o bot e o proxy juntos**: Execute o script `start_openkore_e_proxy.bat` localizado na pasta `plugins/aiChat/`. Este script iniciará automaticamente o OpenKore e o servidor proxy Node.js em segundo plano.
2.  **Carregue o Plugin**: No console do OpenKore, digite `plugins load aiChat`.
3.  O bot agora responderá a mensagens privadas com a IA configurada.

### Comandos do Console (`aichat`)

*   `aichat help`: Mostra comandos.
*   `aichat status`: Status e infos do personagem.
*   `aichat config`: Configurações atuais.
*   `aichat set <chave> <valor>`: Define um valor.
*   `aichat provider <openai|deepseek>`: Altera o provedor.

## 4. Solução de Problemas

*   **`Error: listen EADDRINUSE: address already in use :::3000`**: Porta 3000 já em uso. Feche processos anteriores do proxy ou use `netstat -ano | findstr :3000` (Windows) / `lsof -i :3000` (Linux/macOS) para encontrar e encerrar o PID.
*   **Erros de `Can't locate module...`**: Módulos Perl ou Node.js não instalados. Verifique "Pré-requisitos".
*   **IA não responde / respostas ruins**: Verifique se o proxy está rodando, a chave de API em `api_proxy.js`, e ajuste o `prompt`, `max_tokens` e `temperature`.
*   **Informações do personagem incorretas**: Verifique os logs de depuração do OpenKore por `[aiChat] Dados do personagem atualizados:`.
