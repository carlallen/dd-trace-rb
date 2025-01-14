# typed: true
# Give access to otherwise private members
module Datadog
  class Writer
    attr_accessor :trace_handler, :service_handler, :worker
  end

  class Tracer
    remove_method :writer
    attr_accessor :writer
  end

  module Workers
    class AsyncTransport
      attr_accessor :transport
    end
  end

  class Context
    remove_method :current_span
    attr_accessor :trace, :sampled, :finished_spans, :current_span
  end

  class Span
    attr_accessor :meta
  end
end
