const http = require('http');
const https = require('https'); // Para fazer requisições HTTPS para as APIs de IA
const fs = require('fs'); // Importar módulo fs

// --- Configurações (Ajuste conforme necessário) ---
const PORT = 3000; // Porta que o servidor Node.js vai escutar
const DEEPSEEK_API_URL = 'https://api.deepseek.com/chat/completions';
const OPENAI_API_URL = 'https://api.openai.com/v1/chat/completions';
const PID_FILE = 'proxy_pid.txt'; // Nome do arquivo para armazenar o PID

const API_KEY = "sk-0ea236bff97e4033aba9c8bb9c45d30b"; // Sua chave de API para a DeepSeek/OpenAI. Configure aqui ou use variáveis de ambiente.

const server = http.createServer((req, res) => {
    if (req.method === 'POST' && req.url === '/proxy') {
        let body = '';
        req.on('data', chunk => {
            body += chunk.toString();
        });

        req.on('end', () => {
            try {
                const requestData = JSON.parse(body);
                const provider = requestData.provider;
                const aiApiUrl = provider === 'openai' ? OPENAI_API_URL : DEEPSEEK_API_URL;
                
                // Remove o provider do payload antes de enviar para a API de IA
                delete requestData.provider; 
                const aiApiPayload = JSON.stringify(requestData);

                const options = {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${API_KEY}`, // Chave API para a DeepSeek/OpenAI
                        'Content-Length': Buffer.byteLength(aiApiPayload)
                    }
                };

                const proxyReq = https.request(aiApiUrl, options, (aiRes) => {
                    let aiResponseBody = '';
                    aiRes.on('data', chunk => {
                        aiResponseBody += chunk.toString();
                    });
                    aiRes.on('end', () => {
                        res.writeHead(aiRes.statusCode, { 'Content-Type': 'application/json' });
                        res.end(aiResponseBody);
                    });
                });

                proxyReq.on('error', (e) => {
                    console.error('Proxy: Erro ao chamar a API de IA:', e.message);
                    res.writeHead(500, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ error: 'Erro ao chamar a API de IA', details: e.message }));
                });

                proxyReq.write(aiApiPayload);
                proxyReq.end();

            } catch (e) {
                console.error('Proxy: Erro ao parsear requisição ou JSON:', e.message);
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'Erro na requisição ou JSON inválido', details: e.message }));
            }
        });
    } else {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not Found');
    }
});

server.listen(PORT, () => {
    const pid = process.pid;
    fs.writeFile(PID_FILE, pid.toString(), (err) => {
        if (err) {
            console.error('Proxy: Erro ao escrever PID para o arquivo:', err);
        } else {
            console.log(`Proxy do AI Chat iniciado na porta ${PORT} com PID ${pid}. PID salvo em ${PID_FILE}`);
        }
    });
    console.log('Aguardando requisições do OpenKore...');
});

// Adicionar tratamento para encerramento do processo
process.on('exit', () => {
    if (fs.existsSync(PID_FILE)) {
        fs.unlinkSync(PID_FILE);
        console.log(`Proxy: Arquivo PID ${PID_FILE} removido.`);
    }
});

process.on('SIGINT', () => {
    server.close(() => {
        console.log('Proxy: Servidor encerrado por SIGINT.');
        process.exit(0);
    });
});

process.on('SIGTERM', () => {
    server.close(() => {
        console.log('Proxy: Servidor encerrado por SIGTERM.');
        process.exit(0);
    });
}); 