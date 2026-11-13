#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "../interactive"
require_relative "../api"
require_relative "client"
require_relative "models"

# The Replicate CLI. Run with no arguments in a terminal and it asks what to do;
# flags still work for scripts; `api '<json>'` is the machine boundary MASTER
# calls. postpro looks for this file as a sibling to decide whether its Replicate
# hand-off is available, so it must stay at this path.
module Studio
  module Replicate
    module CLI
      module_function

      MODELS = Studio::ReplicateClient::Models

      # The API actions. Each returns JSON-serializable data; MASTER reaches
      # these through the subprocess boundary without ever seeing a prompt.
      def actions
        {
          "catalogue" => ->(_request) { catalogue },
          "free" => ->(_request) { MODELS.free_models },
          "account" => ->(_request) { { "username" => Studio::ReplicateClient.new.account_username } },
          "render" => ->(request) { render(request) },
        }
      end

      def catalogue
        MODELS.engines.map do |name, spec|
          {
            "name" => name,
            "likeness" => spec["likeness"],
            "free" => !!spec["free"],
            "inputs" => Array(spec["inputs"]),
            "default" => name == MODELS.default_engine,
          }
        end
      end

      def render(request)
        prompt = request["prompt"].to_s
        raise ArgumentError, "render needs a prompt" if prompt.empty?

        engine = request["engine"] || MODELS.default_engine
        client = Studio::ReplicateClient.new
        output = client.predict(engine, { "prompt" => prompt }, timeout: request.fetch("timeout", 600))
        written = request["out"]
        client.download_url(Array(output).first, written) if written
        { "engine" => engine, "output" => output, "written" => written }
      end

      def run(argv)
        return Studio::Api.respond(actions, argv:) if Studio::Api.requested?(argv)

        options = {}
        parser = OptionParser.new do |p|
          p.on("--catalogue", "list the STUDIO model catalogue") { options[:catalogue] = true }
          p.on("--free", "list the free-tier models") { options[:free] = true }
          p.on("--account", "show the connected Replicate account") { options[:account] = true }
          p.on("--render PROMPT", "run one prediction") { |v| options[:render] = v }
          p.on("--engine NAME", "engine for --render") { |v| options[:engine] = v }
          p.on("--out FILE", "write the --render output here") { |v| options[:out] = v }
        end

        wizard = Studio::Interactive.new
        if argv.empty? && wizard.tty?
          choice = wizard.choose("What would you like to do?", [
            ["See what STUDIO can render", :catalogue],
            ["Check the Replicate connection", :account],
            ["Render one picture", :render],
            ["See the free-tier models", :free],
          ])
          case choice
          when :catalogue then options[:catalogue] = true
          when :free then options[:free] = true
          when :account then options[:account] = true
          when :render
            options[:render] = wizard.ask("Describe the picture")
            options[:engine] = wizard.ask("Engine", default: MODELS.default_engine)
            options[:out] = wizard.ask("Write the file to", default: "replicate.png")
          end
        else
          parser.parse!(argv)
          options[:catalogue] = true if options.empty?
        end

        if options[:catalogue]
          catalogue.each do |row|
            marks = []
            marks << "default" if row["default"]
            marks << "free" if row["free"]
            puts format("%-38s %-9s %-16s %s", row["name"], row["likeness"], marks.join(","), row["inputs"].join(", "))
          end
          return
        end

        if options[:free]
          MODELS.free_models.each { |name| puts name }
        elsif options[:account]
          puts "account: #{Studio::ReplicateClient.new.account_username}"
        elsif options[:render]
          puts JSON.generate(render("prompt" => options[:render], "engine" => options[:engine], "out" => options[:out]))
        end
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  status = Studio::Replicate::CLI.run(ARGV)
  exit(status.is_a?(Integer) ? status : 0)
end
