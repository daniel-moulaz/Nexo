/// How to plug the Nexo connector (a standard MCP server over HTTP, with the
/// access token in the address) into each assistant client. The address is
/// the secret: every recipe embeds it, so they are shown only to the person.
class McpRecipe {
  const McpRecipe(this.client, this.steps, this.snippet);
  final String client, steps, snippet;
}

List<McpRecipe> mcpClientRecipes(String address) {
  final json = '{"url": "$address"}';
  return [
    McpRecipe(
        'Claude (app e site)',
        'Configurações → Conectores → Adicionar conector personalizado. Nome: Nexo. URL: o endereço. Numa conversa, ative o conector.',
        address),
    McpRecipe('Claude Code', 'No terminal:',
        'claude mcp add --transport http nexo "$address" --scope user'),
    McpRecipe(
        'Cursor',
        'Settings → MCP → Add new global MCP server (abre o mcp.json):',
        '{"mcpServers": {"nexo": $json}}'),
    McpRecipe(
        'VS Code (Copilot)',
        'Command Palette → "MCP: Add Server" → HTTP, ou no mcp.json:',
        '{"servers": {"nexo": {"type": "http", "url": "$address"}}}'),
    McpRecipe('Gemini CLI', 'Em ~/.gemini/settings.json:',
        '{"mcpServers": {"nexo": {"httpUrl": "$address"}}}'),
    McpRecipe('Codex CLI', 'Em ~/.codex/config.toml:',
        '[mcp_servers.nexo]\nurl = "$address"'),
  ];
}
