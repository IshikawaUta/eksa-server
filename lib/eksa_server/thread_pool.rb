# lib/eksa_server/thread_pool.rb
require 'thread'

module EksaServer
  class ThreadPool
    attr_reader :spawned, :waiting

    def initialize(min, max, &block)
      @min, @max = min, max
      @block = block
      @todo = Queue.new
      @pool = []
      @spawned = 0
      @waiting = 0
      @mutex = Mutex.new
      @min.times { spawn_thread }
    end

    def <<(work)
      @mutex.synchronize do
        if @waiting == 0 && @spawned < @max
          spawn_thread
        end
      end
      @todo << work
    end

    def shutdown
      @spawned.times { @todo << :exit }
      @pool.each(&:join)
    end

    private

    def spawn_thread
      @mutex.synchronize do
        @spawned += 1
        thread = Thread.new do
          loop do
            @mutex.synchronize { @waiting += 1 }
            work = @todo.pop
            @mutex.synchronize { @waiting -= 1 }
            break if work == :exit
            @block.call(work) rescue nil
          end
          @mutex.synchronize { @spawned -= 1 }
        end
        @pool << thread
      end
    end
  end
end
