# frozen_string_literal: true

require_relative "../tools/law_instrument_runner"

instrument_id = ENV["PUB5_LAW_INSTRUMENT_ID"].to_s
abort "PUB5_LAW_INSTRUMENT_ID is required" if instrument_id.empty?

exit Operator::LawInstrumentRunner.run(instrument_id)
