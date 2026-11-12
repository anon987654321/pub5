# frozen_string_literal: true

# Wears-well-with, right-sized for a personal wardrobe.
#
# The gap ledger's ask was explicit: start from owner-tagged typed attributes,
# not a pgvector migration for a wardrobe of a few hundred garments. Every
# dimension here is one typed field the owner (or Amber's tagging) already
# maintains — category, color, material, season, mood, life phase and the
# occasion tags — so a match can always answer "because both are summer wool
# work wear" and never "because the model said 0.83". The similarity is plain
# cosine over binary token vectors, brute-forced across the wardrobe: at
# wardrobe scale the whole scan is milliseconds, and an index would only hide
# which items were compared.
#
# Deliberately absent: embeddings, wear counts and price. Wears-well-with is
# about what goes together; how often it was worn is the analytics surface's
# answer, and "expensive" is nobody's taste.
class WearsWellWith
  # The typed fields that describe what a garment is. occasion_tags is a
  # space-separated string column and contributes one token per tag.
  TOKEN_FIELDS = %w[category color material season mood_effect life_phase].freeze
  OCCASION_FIELD = "occasion_tags"

  attr_reader :item

  def initialize(item)
    @item = item
  end

  # The nearest garments in the same wardrobe, best first. Each result carries
  # the match and the shared tokens that caused it, so a reader can judge the
  # reason and not only the number.
  def neighbors(limit: 4, minimum: 0.2)
    candidates = Item.where(user_id: item.user_id).where.not(id: item.id)
                     .where(lifecycle_state: "active")
    candidates.filter_map do |other|
      similarity, shared = compare(other)
      next if shared.empty? || similarity < minimum

      { item: other, similarity: similarity.round(3), shared: shared }
    end.sort_by { |match| -match[:similarity] }.first(limit)
  end

  # Cosine over binary vectors is |A ∩ B| / sqrt(|A| · |B|). Returns the score
  # and the shared tokens, so the caller never has to recompute the why.
  def compare(other)
    mine = tokens
    theirs = self.class.tokens_for(other)
    shared = (mine & theirs).sort
    return [ 0.0, [] ] if shared.empty? || mine.empty? || theirs.empty?

    [ shared.size / Math.sqrt(mine.size * theirs.size), shared ]
  end

  def tokens = self.class.tokens_for(item)

  # One token per typed value, namespaced by field so "blue" the color and
  # "blue" a mood can never meet. Blank and placeholder values contribute
  # nothing; an item with no typed attributes matches nothing, which is the
  # honest answer rather than a guess.
  def self.tokens_for(record)
    tokens = TOKEN_FIELDS.filter_map do |field|
      value = record.public_send(field)
      # .to_s over present?: the tokeniser stays pure Ruby, so the contract
      # suite can run it on a bare interpreter without ActiveSupport loaded.
      next if value.nil? || value.to_s.strip.empty?

      "#{field}:#{value.to_s.strip.downcase}"
    end
    tags = record.public_send(OCCASION_FIELD).to_s.strip.downcase.split
    tokens.concat(tags.map { |tag| "#{OCCASION_FIELD}:#{tag}" })
    tokens.uniq
  end
end
