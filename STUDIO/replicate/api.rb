# frozen_string_literal: true

require "json"
require "stringio"

module Studio
  # The machine boundary for the STUDIO tools.
  #
  # Each tool is an interactive CLI for a person and an API for MASTER. This is
  # the API half: one request in, one JSON response out, over the same
  # subprocess boundary MASTER already uses, so MASTER never meets a prompt and
  # never has to parse a human's progress lines.
  #
  #   ruby STUDIO/dilla/dilla.rb api '{"action":"list"}'
  #   ruby STUDIO/lora/lora.rb  api '{"action":"validate","subject":"ragnhild"}'
  #
  # The request is a JSON object whose "action" names a handler the tool
  # registers; the remaining keys are that handler's arguments. The response is
  # always a single JSON object: {"ok":true,"result":…} or {"ok":false,"error":…}.
  # Exit status is 0 on ok and 1 on error, so a caller may check either.
  module Api
    module_function

    # True when argv asks for the API rather than the interactive CLI.
    def requested?(argv) = argv.first == "api"

    # Run one API request. `actions` maps an action name (String) to a callable
    # that takes the request Hash (string keys) and returns a JSON-serializable
    # result. Writes exactly one JSON line to `output` and returns the status.
    #
    # The handler runs with $stdout and $stderr captured, so a tool that prints
    # progress while it works still leaves the JSON the only thing on the wire.
    # The captured chatter rides back under "output" for a caller that wants it.
    def respond(actions, argv:, input: $stdin, output: $stdout)
      request = read_request(argv, input)
      action = request["action"].to_s
      handler = actions[action]
      raise ArgumentError, "unknown action #{action.inspect}; known: #{actions.keys.sort.join(', ')}" unless handler

      result, chatter = capture { handler.call(request) }
      payload = { "ok" => true, "result" => result }
      payload["output"] = chatter unless chatter.empty?
      output.puts(JSON.generate(payload))
      0
    rescue StandardError => error
      output.puts(JSON.generate("ok" => false, "error" => "#{error.class}: #{error.message}"))
      1
    end

    # Run the block with the process's standard streams diverted to buffers.
    def capture
      out = StringIO.new
      err = StringIO.new
      original_out = $stdout
      original_err = $stderr
      $stdout = out
      $stderr = err
      value = yield
      [value, [out.string, err.string].reject(&:empty?).join]
    ensure
      $stdout = original_out
      $stderr = original_err
    end

    # The request is the JSON after "api", or stdin when none was given, so a
    # caller can pass a large request without a shell-quoting limit.
    def read_request(argv, input)
      payload = argv[1]
      payload = input.read if payload.nil? || payload.empty?
      raise ArgumentError, "empty API request" if payload.to_s.strip.empty?

      parsed = JSON.parse(payload)
      raise ArgumentError, "API request must be a JSON object" unless parsed.is_a?(Hash)

      parsed
    end
  end
end
