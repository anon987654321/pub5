# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:309 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0f81c5f2d889dea3
require_relative "master/law/javascript"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:MAGIC_COLOR) do
          tags %i[DESIGN]
          fix "color values must reference design tokens, not raw hex/rgb"
          bad ".btn { color: #c0392b; }\n"
          good ":root { --danger: #c0392b; }\n"
          check do |src, path|
            next [] if path.to_s.match?(%r{/spec/|/test/})
            next [] if File.basename(path.to_s).match?(/\Aface\.part\d+\.txt\z/)
            # A documented brand parody or a token source declares raw colors
            # intentional with `scan: intentional-colors` in its head; one line opts
            # out with an inline `scan: intentional`. A `--x:`/`$x:` line is a token
            # definition — where a raw value belongs — not a usage that should cite one.
            next [] if src.lines.first(20).join.match?(/scan:\s*intentional-colors/)
            # Email cannot use custom properties. Outlook, Gmail's web client and
            # every other mail renderer drop var() and leave the declaration
            # unresolved, so _mailer_styles.html.erb is written in hex on purpose —
            # 25 findings telling the one file that must not cite a token to cite
            # one. The rest of the fleet is unaffected by this exemption because
            # nothing else renders into a mail client.
            next [] if path.to_s.match?(/mailer/)
            # The OS-level colour declarations, which are not CSS and cannot hold a
            # var(). A web app manifest is JSON the operating system reads to paint
            # the task switcher and splash screen, and <meta name="theme-color">
            # colours the browser chrome itself — both take a literal or nothing.
            next [] if File.basename(path.to_s).start_with?("manifest.json")

            # Anchored to line start OR to an opening brace, because a theme override
            # is routinely written on one line: `:root { --border: #2c2824; }` inside
            # a media query. Anchored only at the start, the guard saw `:root {` and
            # called the definition a usage — and this was the last MAGIC_COLOR
            # finding in the tree that looked substitutable, which is what sent me
            # looking at it.
            definition = /(?:\A|\{)\s*(--[\w-]+|\$[\w-]+)\s*:/
            messages = {
              # (?<![\w-]): a # preceded by a word char is not a colour — Stimulus
              # action descriptors (nested-form#add) spell controller#method.
              /(?<![\w-])#[0-9a-fA-F]{3,6}\b/ => "raw hex color - use CSS custom property or design token",
              # rgb(from var(--x) ...) is relative colour syntax DERIVING from
              # the token — that is citing it, not bypassing it.
              /\brgba?\s*\((?!from\s+var\()/ => "raw rgb() color - use CSS custom property or design token",
              /\bhsla?\s*\(/ => "raw hsl() color - use CSS custom property or design token",
            }
            # Comment lines blanked, which is what without_comment_lines exists for
            # and what its own note predicts: "a comment that names the thing the
            # rule forbids [becomes] a finding about itself". Here that was a
            # comment explaining *why* a colour was chosen — `// #d8d6e0 is brgen's
            # own --text` — reported as a raw colour, and the note recording that a
            # source pen used #fe9900 reported as a colour to tokenise.
            #
            # Canvas is the other one. `ctx.fillStyle = "#222"` is not a style
            # choice avoiding a token, it is the only form the 2D context accepts:
            # CSS custom properties do not resolve inside canvas, WebGL or Three.js
            # material colours. Asking these to cite a token asks for something that
            # does not render.
            canvas_sink = /\b(?:fillStyle|strokeStyle|shadowColor|backgroundColor|setHexColor)\b|\bnew\s+THREE\.Color\b|theme-color|theme_color/
            scanned = without_var_fallbacks(without_block_comments(without_erb_comments(without_comment_lines(src))))
            # Stylesheets get the value-position filter; JS and HTML do not, because
            # a colour there is an argument or an attribute, not a declaration.
            scanned = declaration_values_only(without_mask_gradients(scanned)) if path.to_s.match?(/\.(css|scss)\z/)
            # Guards read the ORIGINAL line, the search reads the filtered one. The
            # value filter strips the `--token:` prefix, so asking `definition` about
            # the filtered line stopped recognising token definitions and counted
            # every one of them — 234 findings became 333 before this was split.
            original = src.lines
            scanned.each_line.with_index(1).flat_map do |line, number|
              raw = original[number - 1].to_s
              next [] if raw.match?(/scan:\s*intentional/) || raw.match?(definition)
              next [] if raw.match?(canvas_sink)

              messages.filter_map { |pattern, message| finding(line: number, message:) if line.match?(pattern) }
            end
          end
        end
      end
    end
  end
end
