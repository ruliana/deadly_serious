module DeadlySerious
  module Engine

    # Restrict IO class that opens ONLY
    # when trying to read something.
    #
    # Also, used to reopend lost connections.
    #
    # By "restrict", I mean it implements
    # just a few IO operations.
    class LazyIo
      def initialize(channel)
        @channel = channel
      end

      def gets
        open_reader
        @io.gets
      end

      def each(&block)
        open_reader
        @io.each &block
      end

      def <<(element)
        open_writer
        @io << element
      end

      def closed?
        @io.nil? || @io.closed?
      end

      def close
        @io.close
        @io = nil
      end

      private

      def open_reader
        if closed?
          @io = @channel.open_reader
        end
      end

      def open_writer
        if closed?
          @io = @channel.open_writer
        end
      end
    end
  end
end
