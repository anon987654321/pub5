# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/brand.rb:47 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6148ae99097138d1
require_relative "master/law/brand"

Law.define(:WORDMASK_OBSERVES_UNCLIPPED) do
  source "Framer Motion + IntersectionObserver - a fully clipped element never intersects"
  # Measured: whileInView on the masked word span (y: 112% inside its own
  # overflow:hidden mask) reports intersection area 0 forever — the headline
  # stayed invisible. Observe the outer, unclipped wrapper; drive the inner
  # spans with animate.
  detect { |line| line.include?("whileInView") && line.match?(/y:\s*'\d+%'/) }
  fix "useInView on the outer wrapper, animate on the inner word spans."
  bad  "<motion.span className=\"wr-word\" initial={{ y: '112%' }} whileInView={{ y: '0%' }}>"
  good "const inView = useInView(outerRef); <motion.span animate={inView ? { y: '0%' } : { y: '112%' }}>"
end
