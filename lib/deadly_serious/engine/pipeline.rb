require 'deadly_serious/engine/channel'
require 'deadly_serious/engine/open_io'
require 'deadly_serious/engine/auto_pipe'
require 'deadly_serious/processes/splitter'

module DeadlySerious
  module Engine
    class Pipeline
      include DeadlySerious::Engine::Commands

      attr_reader :data_dir, :pipe_dir

      def initialize(data_dir: './data',
                     pipe_dir: "/tmp/deadly_serious/#{Process.pid}",
                     preserve_pipe_dir: false)
        @data_dir = data_dir
        @pipe_dir = pipe_dir
        @pids = []
        Channel.config(data_dir, pipe_dir, preserve_pipe_dir)
      end

      def run
        Channel.setup
        run_pipeline
        wait_children
      rescue => e
        kill_children
        raise e
      ensure
        Channel.teardown
      end

      # Wait all sub processes to finish before
      # continue the pipeline.
      #
      # Always prefer to use {DeadlySerious::Engine::Commands#spawn_capacitor}
      # if possible.
      def wait_processes!
        wait_children
      end

      # Spawn a  class in a separated process.
      #
      # This is a basic command, use it only if you have
      # more than one input or output pipe. Otherwise
      # prefer the simplier {DeadlySerious::Engine::Commands#spawn_class}
      # method.
      def spawn_process(a_class, *args, process_name: a_class.name, readers: [], writers: [])
        writers.each { |writer| create_pipe(writer) }
        fork_it do
          begin
            set_process_name(process_name, readers, writers)
            append_open_io_if_needed(a_class)
            the_object = a_class.new
            the_object.run(*args, readers: readers, writers: writers)
          rescue Errno::EPIPE # Broken Pipe, no problem
            # Ignore
          ensure
            the_object.finalize if the_object.respond_to?(:finalize)
          end
        end
      end

      def spawn_command(a_shell_command)
        command = a_shell_command.dup
        a_shell_command.scan(/\(\((.*?)\)\)/) do |(pipe_name)|
          pipe_path = create_pipe(pipe_name)
          command.gsub!("((#{pipe_name}))", "'#{pipe_path.gsub("'", "\\'")}'")
        end
        @pids << spawn(command)
      end

      private

      def append_open_io_if_needed(a_class)
        a_class.send(:prepend, OpenIo) unless a_class.include?(OpenIo)
      end

      def create_pipe(pipe_name)
        Channel.create_pipe(pipe_name)
      end

      def fork_it
        @pids << fork { yield }
      end

      def wait_children
        @pids.each { |pid| Process.wait(pid) }
        @pids.clear
      end

      def kill_children
        @pids.each { |pid| Process.kill('SIGTERM', pid) rescue nil }
        wait_children
      end

      def set_process_name(name, readers, writers)
        $0 = "ruby #{self.class.dasherize(name)} <(#{readers.join(' ')}) >(#{writers.join(' ')})"
      end

      def self.dasherize(a_string)
        a_string.gsub(/(.)([A-Z])/, '\1-\2').downcase.gsub(/\W+/, '-')
      end
    end
  end
end