require 'stackprof'

module Datadog
  module Profiling
    # Provides an object that serves at the same time as a collector (using stackprof) and
    # as a recorder (collects the stackprof results)
    class StackProfCollectorRecorder
      def initialize
        @recorder = Datadog::Profiling::Recorder.new(
          [Datadog::Profiling::Events::StackSample],
          0 # no max size
        )
        @stack_sample_event_recorder = @recorder[Datadog::Profiling::Events::StackSample]

        # Cache this proc, since it's pretty expensive to keep recreating it
        @build_backtrace_location = method(:build_backtrace_location).to_proc

        @needs_flushing = false
      end

      def start
        StackProf.start(mode: mode, raw: true, aggregate: false)
        Datadog.logger.debug("Started stackprof profiling in #{mode}")
        @needs_flushing = true
      end

      def mode
        @mode ||= ENV['DD_PROFILING_STACKPROFHACK_CPU'] == 'true' ? :cpu : :wall
      end

      def stop(*_)
        StackProf.stop
        Datadog.logger.debug("Stopped stackprof profiling")
      end

      def enabled=(*_)
      end

      def empty?
        !@needs_flushing
      end

      def flush
        @needs_flushing = false

        was_running = StackProf.running?
        StackProf.stop if was_running
        profile = StackProf.results
        start if was_running

        #Datadog.logger.debug "Flushing stackprof profile with"
        #StackProf::Report.new(profile).print_text

        profile_to_recorder(profile)
        Datadog.logger.debug "Successfully put stackprof results into recorder"

        @recorder.flush
      end

      private

      def profile_to_recorder(profile)
        frames = profile.fetch(:frames)

        raw_samples = profile[:raw] || []
        raw_timestamps = profile[:raw_timestamp_deltas] || []

        events = []

        all_backtrace_locations = frames_to_backtrace_locations(frames)

        sample_position = 0
        raw_timestamps_position = 0

        while sample_position < raw_samples.size
          length = raw_samples[sample_position]
          stack_start_position = sample_position + 1
          stack_end_position = sample_position + length
          count_position = stack_end_position + 1

          the_samples = raw_samples[stack_start_position..stack_end_position]
          count = raw_samples[count_position]
          timestamps_in_microseconds = raw_timestamps[raw_timestamps_position...(raw_timestamps_position + count)]
          raise 'Raw timestamps missing' unless timestamps_in_microseconds.size == count

          sample_time = timestamps_in_microseconds.reduce(:+) * 1000

          events << Events::StackSample.new(
            0, # fake timestamp -- avoids using Time.now
            the_samples.reverse.map { |sample| all_backtrace_locations.fetch(sample) },
            the_samples.size,
            :unsupported, # thread_id
            nil, # trace_id
            nil, # span_id
            nil, # trace_resource_container
            (sample_time if mode == :cpu), # cpu time
            (sample_time unless mode == :cpu), # "wall clock-ish" time
          )

          sample_position = count_position + 1
          raw_timestamps_position += count
        end

        @recorder.push(events) unless events.empty?
      end

      def frames_to_backtrace_locations(frames)
        frames.each_with_object({}) do |(key, frame), locations|
          locations[key] = @stack_sample_event_recorder.cache(:backtrace_locations).fetch(
            frame.fetch(:name),
            frame[:line] || 0,
            frame.fetch(:file),
            &@build_backtrace_location
          )
        end
      end

      def build_backtrace_location(_id, base_label, lineno, path)
        string_table = @stack_sample_event_recorder.string_table

        Profiling::BacktraceLocation.new(
          string_table.fetch_string(base_label),
          lineno,
          string_table.fetch_string(path)
        )
      end
    end
  end
end