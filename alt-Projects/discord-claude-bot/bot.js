require("dotenv").config({ path: __dirname + "/.env" });

const { Client, GatewayIntentBits, Partials, AttachmentBuilder } = require("discord.js");
const Anthropic = require("@anthropic-ai/sdk").default;

const discord = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
  ],
  partials: [Partials.Message],
});

const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY,
});

// Per-channel conversation history (last 20 messages)
const conversationHistory = new Map();
const MAX_HISTORY = 20;

function getHistory(channelId) {
  if (!conversationHistory.has(channelId)) {
    conversationHistory.set(channelId, []);
  }
  return conversationHistory.get(channelId);
}

function addToHistory(channelId, role, content) {
  const history = getHistory(channelId);
  history.push({ role, content });
  if (history.length > MAX_HISTORY) {
    history.splice(0, history.length - MAX_HISTORY);
  }
}

discord.on("messageCreate", async (message) => {
  if (message.author.bot) return;
  if (!message.mentions.has(discord.user)) return;

  const prompt = message.content.replace(/<@!?\d+>/g, "").trim();
  if (!prompt) return;

  const typingInterval = setInterval(() => message.channel.sendTyping(), 5000);
  await message.channel.sendTyping();

  addToHistory(message.channel.id, "user", prompt);

  try {
    const response = await anthropic.messages.create({
      model: "claude-sonnet-4-6",
      max_tokens: 4096,
      system:
        `You are a witty, sharp-tongued AI hanging out in a Discord server with friends. You speak French by default (unless spoken to in another language).

Your personality:
- You're playful, teasing, and sarcastic when the vibe is casual. You roast people (with love) and match their energy.
- When someone jokes, you escalate with dark humor, irony, or absurd comebacks. Be funny, not polite.
- When someone asks a serious/technical question, you switch to being genuinely helpful and precise — no bullshit.
- You NEVER use corporate-speak, filler phrases like "Great question!", or excessive politeness. No "N'hésitez pas à demander!" energy.
- Keep responses short and punchy. You're texting in a Discord server, not writing an essay.
- You can use emojis sparingly when it adds to the humor.
- You have web search available — use it when asked about current events, news, or real-time data.`,
      messages: getHistory(message.channel.id),
      tools: [{ type: "web_search_20250305", name: "web_search", max_uses: 5 }],
    });

    clearInterval(typingInterval);

    // Extract final text from response (may contain tool_use + text blocks)
    const reply = response.content
      .filter((block) => block.type === "text")
      .map((block) => block.text)
      .join("\n\n");

    addToHistory(message.channel.id, "assistant", reply);

    if (!reply) {
      await message.reply("I got an empty response. Try again?");
      return;
    }

    // Extract code blocks and send as file attachments
    const codeBlockRegex = /```(\w*)\n([\s\S]*?)```/g;
    const codeBlocks = [];
    let textOnly = reply;
    let match;

    while ((match = codeBlockRegex.exec(reply)) !== null) {
      codeBlocks.push({ lang: match[1] || "txt", code: match[2].trim() });
    }

    // If response is long or has code blocks, send as file(s)
    if (reply.length > 2000 && codeBlocks.length > 0) {
      textOnly = textOnly.replace(codeBlockRegex, "[see attached file]").trim();
      if (textOnly.length > 0) {
        for (let i = 0; i < textOnly.length; i += 2000) {
          await message.reply(textOnly.substring(i, i + 2000));
        }
      }
      const extMap = { js: "js", javascript: "js", ts: "ts", typescript: "ts", python: "py", py: "py", java: "java", html: "html", css: "css", json: "json", sql: "sql", sh: "sh", bash: "sh", yaml: "yaml", yml: "yaml", xml: "xml", go: "go", rust: "rs", c: "c", cpp: "cpp", rb: "rb", php: "php" };
      for (let i = 0; i < codeBlocks.length; i++) {
        const ext = extMap[codeBlocks[i].lang] || codeBlocks[i].lang || "txt";
        const filename = `code${codeBlocks.length > 1 ? i + 1 : ""}.${ext}`;
        const attachment = new AttachmentBuilder(Buffer.from(codeBlocks[i].code), { name: filename });
        await message.reply({ files: [attachment] });
      }
    } else if (reply.length > 2000) {
      const attachment = new AttachmentBuilder(Buffer.from(reply), { name: "response.txt" });
      await message.reply({ files: [attachment] });
    } else {
      await message.reply(reply);
    }
  } catch (err) {
    clearInterval(typingInterval);
    console.error("Claude API error:", err.message);
    await message.reply("Sorry, something went wrong. Please try again.");
  }
});

discord.once("ready", () => {
  console.log(`Bot online as ${discord.user.tag}`);
});

discord.login(process.env.DISCORD_TOKEN);
