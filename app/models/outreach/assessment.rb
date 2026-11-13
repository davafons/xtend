class Outreach::Assessment
  TOPICS = {
    "Rails and databases" => [/rails|ruby|sqlite|products/i, /\b(ruby|sqlite|hotwire|activerecord|postgres|database|migration)\b/i],
    "Coding agents and developer workflows" => [/agent|coding|developer|workflow|tools/i, /\b(coding agents?|claude code|codex|opencode|mcp|agents? (run|running|stuck|workflow)|debugging|developer|devtools|backend|software engineer|agent.{0,30}(context|diagnosis|stuck|tab|code))\b/i],
    "Japanese learning" => [/japan|language|learning/i, /\b(japanese|kanji|furigana|anki|jlpt)\b/i],
    "Local-first tools" => [/local|personal data|self.host/i, /\b(local.first|self.hosted|offline|obsidian|sqlite|personal data)\b/i]
  }.freeze
  AVOID = /\b(airdrop|testnet|memecoin|crypto|blockchain|web3|bonding curve|transaction volume|uniswap|defi|nft|agent economy|free stealth|completely free|daily dose of ai|copy all four|masterclass|book b2b sales meetings|follow.for.follow)\b|like and (retweet|repost)|retweet to win/i
  QUESTION = /\?|\b(debug|bug|trade.?off|migration|latency|tried|learned|testing|experiment|stuck|diagnosis)\b/i

  def self.call(body:, description:, interests:, selected: false, handle: nil)
    text = [body, description].compact.join(" ")
    return {rank: -100, reason: "Automated accounts are excluded from builder discovery."} if handle.to_s.casecmp?("grok")
    return {rank: -100, reason: "Excluded by your promotion, hype, or crypto filters."} if text.match?(AVOID)
    topics = TOPICS.filter_map do |name, (interest, terms)|
      matches = text.match?(terms)
      if name == "Rails and databases" && text.match?(/\brails\b/i)
        matches ||= text.match?(/\b(ruby|hotwire|software|ecommerce|routing|framework|developer|app|code|server|backend|active.?record)\b/i)
      end
      name if interests.any? { |value| value.match?(interest) } && matches
    end
    if topics.empty? && !selected
      return {rank: -10, reason: "No concrete match to your current builder interests."}
    end
    question = body.match?(QUESTION)
    reason = selected ? "You saved this source for review." : "Matches #{topics.join(' and ')}."
    reason += " Contains a question or an implementation problem." if question
    {rank: topics.size * 10 + (question ? 20 : 0) + (body.include?("?") ? 15 : 0), reason: reason}
  end
end
