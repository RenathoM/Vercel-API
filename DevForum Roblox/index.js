// Configurações do Monitor Local (Node.js)
const TOPIC_ID = "4751465";
const ROBLOX_TOPIC_URL = `https://devforum.roblox.com/t/${TOPIC_ID}.json`; 
const DISCORD_WEBHOOK_URL = "https://discord.com/api/webhooks/1418572542607622154/Nf1wIq7nM41lSHiziL2TIKDbvoxlbFRg_62xGxYjnq-ngoRHTmRGN5eXp7Y288xKAsMi";
const ROLE_PING_ID = "1292273276013379765"; // ID da role do Discord para pingar
const CHECK_INTERVAL_MS = 60000; // 60 segundos

let lastCheckedPostNumber = 0;
let lastSentPostId = null;

function log(message) {
    const time = new Date().toLocaleTimeString('pt-BR');
    console.log(`[${time}] ${message}`);
}

function stripHtmlTags(htmlContent) {
    if (!htmlContent) return "";
    return htmlContent.replace(/<[^>]*>?/gm, '').trim();
}

function extractImage(htmlContent) {
    if (!htmlContent) return null;
    const match = htmlContent.match(/<img[^>]+src="([^">]+)"/);
    return match ? match[1] : null;
}

async function checkDevForum() {
    log("Verificando atualizações no DevForum...");
    try {
        const topicResponse = await fetch(ROBLOX_TOPIC_URL, {
            headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' }
        });
        
        if (!topicResponse.ok) throw new Error(`Falha ao acessar tópico: ${topicResponse.status}`);
        
        const topicData = await topicResponse.json();
        const topicTitle = topicData.title;
        const highestPostNumber = topicData.highest_post_number; 
        
        const stream = topicData.post_stream.stream; 
        const latestPostId = stream[stream.length - 1]; 

        if (latestPostId === lastSentPostId) {
            log(`Post #${latestPostId} já foi notificado anteriormente. Ignorando duplicata.`);
            lastCheckedPostNumber = highestPostNumber;
            return;
        }

        if (lastCheckedPostNumber === 0 || highestPostNumber > lastCheckedPostNumber) {
            const postResponse = await fetch(`https://devforum.roblox.com/posts/${latestPostId}.json`, {
                headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' }
            });
            
            if (!postResponse.ok) throw new Error(`Falha ao acessar o post mais recente: ${postResponse.status}`);
            
            const latestPost = await postResponse.json();

            // Busca posts anteriores recentes no stream para compor comentários/extras
            let extraComments = [];
            if (stream.length > 1) {
                const recentIds = stream.slice(-3, -1);
                for (const id of recentIds) {
                    try {
                        const res = await fetch(`https://devforum.roblox.com/posts/${id}.json`, {
                            headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' }
                        });
                        if (res.ok) {
                            const pData = await res.json();
                            extraComments.push(`**@${pData.username}:** ${stripHtmlTags(pData.cooked).substring(0, 90)}...`);
                        }
                    } catch (err) {
                        // Ignora falhas individuais de requisição de comentários
                    }
                }
            }

            if (lastCheckedPostNumber === 0) {
                lastCheckedPostNumber = highestPostNumber;
                lastSentPostId = latestPostId;
                log(`Iniciando sistema. Tópico tem ${highestPostNumber} posts. Enviando o mais recente como teste...`);
                await sendDiscordWebhook(latestPost, topicTitle, extraComments, true);
            } else {
                log(`NOVO POST DETECTADO! (Post #${highestPostNumber})`);
                await sendDiscordWebhook(latestPost, topicTitle, extraComments, false);
                lastCheckedPostNumber = highestPostNumber;
                lastSentPostId = latestPostId;
            }
        } else {
            log(`Nenhum post novo. (Último post no fórum: #${highestPostNumber})`);
        }

    } catch (error) {
        log(`Erro: ${error.message}`);
    }
}

async function sendDiscordWebhook(post, topicTitle, extraComments, isTest = false) {
    const plainTextContent = stripHtmlTags(post.cooked).substring(0, 3500); 
    const imageUrl = extractImage(post.cooked);
    const likeCount = post.like_count || 0;
    
    // Geração do timestamp dinâmico do Discord
    const unixTimestamp = Math.floor(new Date(post.created_at).getTime() / 1000);
    const timeAgoTag = `<t:${unixTimestamp}:R>`;

    const messagePrefix = isTest 
        ? `**[TESTE DE INICIALIZAÇÃO DO MONITOR]**\n<@&${ROLE_PING_ID}> Aqui está o último anúncio/resposta no DevForum! (Publicado ${timeAgoTag})`
        : `<@&${ROLE_PING_ID}> Novo anúncio/resposta no DevForum! (Publicado ${timeAgoTag})`;

    const embedPayload = {
        title: topicTitle,
        url: `https://devforum.roblox.com/t/${TOPIC_ID}/${post.post_number}`,
        description: plainTextContent,
        color: 16711680, 
        timestamp: new Date(post.created_at).toISOString(),
        author: {
            name: post.username, // Nome puro do usuário, pois marcações de tempo não renderizam corretamente no autor/título do embed
            url: `https://devforum.roblox.com/u/${post.username}`,
            icon_url: `https://devforum.roblox.com/user_avatar/devforum.roblox.com/${post.username}/120/1.png`
        },
        fields: [
            {
                name: "❤️ Curtidas",
                value: `${likeCount} curtida(s)`,
                inline: true
            },
            ...(extraComments && extraComments.length > 0 ? [{
                name: "💬 Comentários / Respostas Recentes",
                value: extraComments.join("\n"),
                inline: false
            }] : [])
        ]
    };

    if (imageUrl) {
        embedPayload.image = { url: imageUrl };
    }

    const payload = {
        content: messagePrefix,
        embeds: [embedPayload]
    };

    try {
        const response = await fetch(DISCORD_WEBHOOK_URL, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(payload)
        });

        if (response.ok) {
            log("Webhook enviado com sucesso para o Discord!");
        } else {
            throw new Error(`Erro do Discord: ${response.status}`);
        }
    } catch (error) {
        log(`Falha ao enviar Webhook: ${error.message}`);
    }
}

// Inicia o monitoramento local
log("Monitor iniciado via Node.js.");
checkDevForum();
setInterval(checkDevForum, CHECK_INTERVAL_MS);