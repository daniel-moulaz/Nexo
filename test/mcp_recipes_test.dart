import 'package:expensy/services/mcp_recipes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every client recipe carries the address and nothing else secret', () {
    const address = 'https://example.supabase.co/functions/v1/nexo-mcp/abc123';
    final recipes = mcpClientRecipes(address);
    expect(recipes.map((r) => r.client), [
      'Claude (app e site)',
      'Claude Code',
      'Cursor',
      'VS Code (Copilot)',
      'Gemini CLI',
      'Codex CLI',
    ]);
    for (final r in recipes) {
      expect(r.snippet, contains(address), reason: r.client);
    }
    expect(recipes[1].snippet, startsWith('claude mcp add --transport http'));
    expect(recipes[2].snippet, contains('"mcpServers"'));
    expect(recipes.last.snippet, contains('[mcp_servers.nexo]'));
  });
}
