# frozen_string_literal: true

module Master
  module Fix
    class RepairLoop
      # Candidates are independent calls against the same unchanged source, so they are asked
      # concurrently and collected in candidate order. MASTER_FIX_PARALLEL_CANDIDATES=0 restores the
      # sequential walk for a lane that punishes concurrent requests.
      #
      # A thread starts with no thread-locals, and the repair keeps its state in them: the refusal note a
      # retry must show the model (RunLedger.retry_note), the model the repair is pinned to (ModelPin),
      # the transcript attempt (FixTrace) and the task contract. Threaded without them, a retry asked the
      # same question again and a pinned repair went to whichever lane answered. So each candidate thread
      # starts with its parent's thread-locals, and a candidate still running when the caller gives up
      # (the file budget's Timeout) is killed rather than left holding a model call.
      module CandidateThreads
        private

        def candidate_threads(count, violation:, event:, &block)
          return Array.new(count) { |index| one_candidate(index, violation:, event:, &block) } if
            ENV["MASTER_FIX_PARALLEL_CANDIDATES"] == "0"

          locals = inherited_thread_locals
          threads = []
          count.times do |index|
            threads << Thread.new do
              Thread.current.report_on_exception = false
              locals.each { |key, value| Thread.current[key] = value }
              one_candidate(index, violation:, event:, &block)
            end
          end
          threads.map(&:value)
        ensure
          # Populate the list before spawning: if a later Thread.new fails,
          # earlier candidates remain reachable. Kill and join on timeout too.
          Array(threads).each { |thread| thread.kill if thread.alive? }
          Array(threads).each do |thread|
            begin
              thread.join
            rescue Exception
              nil
            end
          end
        end

        # Ruby's own bookkeeping keys (__recursive_key__ and the like) belong to the thread that made them.
        def inherited_thread_locals
          Thread.current.keys.reject { |key| key.to_s.start_with?("__") }.to_h { |key| [key, Thread.current[key]] }
        end

        # One candidate's whole lifecycle, sequential or threaded, with the per-candidate rescue.
        def one_candidate(index, violation:, event:, &block)
          Thread.current[:master_llm_answer_model] = nil
          Thread.current[:master_fix_candidate_author_models] = []
          block.call(index)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RepairLoop.propose_candidates", rule: @law.id)
          handle_fix_exception(e, violation, event:)
          nil
        end
      end
    end
  end
end
