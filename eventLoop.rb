class IOLoop
  def initialize
    @streams = []
  end

  def <<(stream)
    @streams << stream
  end

  def run!
    @running = true

    while @running do
      tick
    end
  end

  def tick
    r, w = IO.select(@streams, @streams)

    r.each do |stream|
      stream.handle_read
    end

    w.each do |stream|
      stream.handle_write
    end
  end

  def stop!
    @running = false
  end

end
 
module EventEmitter
  def callbacks
   @_callbacks ||= Hash.new { |h, k| h[k] = [] }
  end

  def emit(type, *args)
    callbacks[type].each do |block|
      block.call(*args)
    end
  end

  def on(type, &block)
    callbacks[type] << block
    self
  end
end

class Stream
  require 'securerandom'
  include EventEmitter

  attr_reader :id

  def initialize(io)
    @io = io
    @writebuffer = ""
    @id = SecureRandom.hex
  end

  def to_io
    @io
  end

  def handle_read
    begin
      chunk = @io.read_nonblock(4096)
      emit(:message, chunk)
    rescue IO::WaitReadable
      # Oops, turned out the IO wasn't actually readable.
    rescue EOFError, Errno::ECONNRESET
      # IO was closed
      emit(:close)
    end
  end

  def <<(chunk)
    @writebuffer << chunk
  end

  def handle_write
    return if @writebuffer.empty?
    begin
      length = @io.write_nonblock(@writebuffer)
      # Remove the data that was successfully written.
      @writebuffer.slice!(0, length)
      # Emit "drain" event if there's nothing more to write.
      emit(:drain) if @writebuffer.empty?
    rescue IO::WaitWritable
    rescue EOFError, Errno::ECONNRESET
      emit(:close)
    end
  end
end

class ConnectionManager
  include EventEmitter

  def initialize(tcp_server)
    @tcp_server = tcp_server
  end

  def to_io; @tcp_server end

  def handle_read
    connection = @tcp_server.accept_nonblock
    emit(:accept, Stream.new(connection))
  end

  def handle_write
    #do not implement
  end
end

require 'socket'

tcp_server = TCPServer.new('0.0.0.0', 8888)
connection_manager = ConnectionManager.new(tcp_server)
clients = []
loop = IOLoop.new

connection_manager.on(:accept) do |connection|
  clients << connection
  connection << "Welcome user ##{connection.id}!\n"
  loop << connection
  connection.on(:message) do |message|
    clients.each do |client|
      next if client.id == connection.id
      client << "User ##{connection.id} said: " + message
    end
  end
end

loop << connection_manager
loop.run!
