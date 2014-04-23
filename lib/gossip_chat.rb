class GossipChat
  VERSION = '1.0'

  def initialize
    @announce    = GossipChat::Announce.new
    @db          = {}
    @lru         = GossipChat::LRU.new
    @peers       = {}
    @peers_mutex = Mutex.new
  end

  def broadcast_addresses
    Thread.new do
      loop do
        @announce.broadcast_addresses
        sleep 30 + rand(30)
      end
    end
  end

  def listen_for_peers
    @announce.listen_for_addresses

    Thread.new do
      loop do
        address = @announce.address_queue.pop
        @peers_mutex.synchronize do
          @peers[address] = true
        end
      end
    end
  end

  def run
    listen_for_peers
    broadcast_addresses

    loop do
      sleep 10
      @peers_mutex.synchronize do
        puts 'addresses'
        puts @peers.keys
      end
    end
  end

end

require 'gossip_chat/announce'
require 'gossip_chat/lru'

