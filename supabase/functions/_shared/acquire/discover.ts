// Discovery — recover a restaurant's OWN website when Places gave us nothing or
// only a platform link. One bounded Claude web_search query (no open-ended
// loop), returning a single own-domain URL or null.

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const DISCOVER_MODEL = Deno.env.get("MENU_MODEL") ?? "claude-sonnet-4-6";

const DISCOVERY_PROMPT =
  `Find the OFFICIAL OWN WEBSITE of the restaurant named below. Return ONLY the
restaurant's own domain URL, nothing else. Do NOT return Wolt, 10bis, Tabit,
Mishloha, Facebook, Instagram, Google Maps, or directory/aggregator links. If the
restaurant appears to have no own website (only platform or social pages), return
exactly: NONE`;

/// Returns an own-site URL string, or null if none found. Single web_search use,
/// at most one pause_turn continuation — bounded for the time budget.
export async function discoverOwnSite(
  name: string,
  area: string | null,
): Promise<string | null> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY is not configured.");

  // deno-lint-ignore no-explicit-any
  const messages: any[] = [{
    role: "user",
    content: `Restaurant: "${name}", ${area ?? "Israel"}, Israel`,
  }];

  let final: Record<string, unknown> | null = null;
  for (let i = 0; i <= 1; i++) {
    const res = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: DISCOVER_MODEL,
        max_tokens: 1024,
        thinking: { type: "disabled" },
        system: DISCOVERY_PROMPT,
        tools: [{ type: "web_search_20260209", name: "web_search", max_uses: 1 }],
        messages,
      }),
    });
    if (!res.ok) throw new Error(`Discovery failed (${res.status})`);
    const data = await res.json();
    if (data.stop_reason === "pause_turn") {
      messages.push({ role: "assistant", content: data.content });
      continue;
    }
    final = data;
    break;
  }
  if (!final) return null;

  const text = (final.content as Array<Record<string, unknown>> | undefined)
    ?.filter((b) => b.type === "text")
    .map((b) => b.text as string)
    .join("")
    .trim() ?? "";

  if (!text || /^NONE\b/i.test(text)) return null;
  // Pull the first URL out of whatever the model returned.
  const match = text.match(/https?:\/\/[^\s)"']+/);
  return match ? match[0] : null;
}
