(function (root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = api;
  }
  root.DiscordNotifier = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  function stripHtmlTags(htmlContent) {
    if (!htmlContent) return '';
    return htmlContent.replace(/<[^>]*>?/gm, '').trim();
  }

  function extractImage(htmlContent) {
    if (!htmlContent) return null;
    const match = htmlContent.match(/<img[^>]+src="([^"]+)"/i);
    return match ? match[1] : null;
  }

  function getDiscordTimestamp(dateString) {
    const unixTimestamp = Math.floor(new Date(dateString).getTime() / 1000);
    return `<t:${unixTimestamp}:R>`;
  }

  function createDiscordPayload({ post, topicTitle, topicId, rolePingId, extraComments = [], isTest = false }) {
    const plainTextContent = stripHtmlTags(post.cooked).substring(0, 3500);
    const imageUrl = extractImage(post.cooked);
    const likeCount = post.like_count || 0;
    const discordTag = getDiscordTimestamp(post.created_at);

    const messagePrefix = isTest
      ? `**[AUDITORIA DE INICIALIZAÇÃO]**\n<@&${rolePingId}> Último post registrado (${discordTag}):`
      : `<@&${rolePingId}> **Novo anúncio publicado (${discordTag})!**`;

    const embedPayload = {
      title: topicTitle,
      url: `https://devforum.roblox.com/t/${topicId}/${post.post_number}`,
      description: plainTextContent,
      color: 16711680,
      timestamp: new Date(post.created_at).toISOString(),
      author: {
        name: post.username,
        url: `https://devforum.roblox.com/u/${post.username}`,
        icon_url: `https://devforum.roblox.com/user_avatar/devforum.roblox.com/${post.username}/120/1.png`
      },
      fields: [
        {
          name: '❤️ Curtidas',
          value: `${likeCount} curtida(s)`,
          inline: true
        },
        ...(extraComments && extraComments.length > 0 ? [{
          name: '💬 Comentários / Respostas Recentes',
          value: extraComments.join('\n'),
          inline: false
        }] : [])
      ]
    };

    if (imageUrl) {
      embedPayload.image = { url: imageUrl };
    }

    return {
      content: messagePrefix,
      embeds: [embedPayload],
      plainTextContent,
      imageUrl,
      likeCount,
      discordTag
    };
  }

  async function sendDiscordWebhook({ webhookUrl, post, topicTitle, topicId, rolePingId, extraComments = [], isTest = false, log = null }) {
    const payload = createDiscordPayload({ post, topicTitle, topicId, rolePingId, extraComments, isTest });

    try {
      const response = await fetch(webhookUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });

      if (!response.ok) {
        throw new Error(`Rejeição da API Discord (Status: ${response.status})`);
      }

      if (log) {
        log('Payload despachado com sucesso para o canal do Discord.', 'success');
      }

      return { ok: true, payload };
    } catch (error) {
      if (log) {
        log(`Falha no despacho do Webhook: ${error.message}`, 'error');
      }
      return { ok: false, error };
    }
  }

  return {
    stripHtmlTags,
    extractImage,
    getDiscordTimestamp,
    createDiscordPayload,
    sendDiscordWebhook
  };
});
