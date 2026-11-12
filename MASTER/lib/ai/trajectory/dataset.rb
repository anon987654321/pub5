# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  module AI
    module Trajectory
      module Dataset
        SCHEMA = "master.llm.sft/v1"

        module_function

        def export(input:, output:)
          FileUtils.mkdir_p(File.dirname(output))
          write_trajectory_records(input, output)
        end

        def write_trajectory_records(input, output)
          count = 0
          File.open(output, "w") do |out|
            File.foreach(input) { |line| count += write_trajectory_record(line, out) }
          end
          count
        end

        def write_trajectory_record(line, out)
          return 0 if line.strip.empty?

          record = JSON.parse(line)
          score = Benchmark.score(record)
          return 0 unless score["verified"]

          out.puts(JSON.generate(
            "schema" => SCHEMA,
            "messages" => messages_for(record),
            "trajectory" => record["events"],
            "score" => score,
            "outcome" => record["outcome"],
          ))
          1
        rescue JSON::ParserError
          0
        end

        def export_preferences(input:, output:)
          records = preference_records(input)
          grouped = records.group_by { |record| record["task"].to_s }
          FileUtils.mkdir_p(File.dirname(output))
          write_preference_groups(grouped, output)
        end

        def preference_records(input)
          File.foreach(input).filter_map do |line|
            next if line.strip.empty?

            JSON.parse(line)
          rescue JSON::ParserError
            nil
          end
        end

        def write_preference_groups(grouped, output)
          count = 0
          File.open(output, "w") do |out|
            grouped.each_value { |group| count += write_preference_group(group, out) }
          end
          count
        end

        def write_preference_group(group, out)
          chosen = group.find { |record| Benchmark.score(record)["verified"] }
          rejected = group.find { |record| !Benchmark.score(record)["verified"] }
          return 0 unless chosen && rejected

          out.puts(JSON.generate(
            "schema" => "master.llm.preference/v1",
            "task" => chosen["task"],
            "chosen" => chosen["events"],
            "rejected" => rejected["events"],
          ))
          1
        end

        def messages_for(record)
          [
            { "role" => "system", "content" => Master::AI::OperatorContract.prompt },
            { "role" => "user", "content" => record["task"].to_s },
            { "role" => "assistant", "content" => JSON.generate(record["events"]) },
          ]
        end
        private_class_method :write_trajectory_records, :write_trajectory_record, :preference_records, :write_preference_groups, :write_preference_group

      end
    end
  end
end
