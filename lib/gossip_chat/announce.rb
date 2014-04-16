require 'ipaddr'
require 'socket'

class GossipChat::Announce

  IPV4 = %w[239.71.79.83]
  PORT = 7380

  def self.ipv6_nonlocal_interfaces
    Socket.getifaddrs.select do |addr|
      addrinfo = addr.addr

      addrinfo.pfamily == Socket::PF_INET6 and not addrinfo.ipv6_unique_local?
    end.map do |addr|
      addr.ifindex
    end.uniq
  end

  IPV6 =
    ipv6_nonlocal_interfaces.map do |ifindex|
      ['ff02::e74f:5353', '::1', ifindex]
    end

  attr_accessor :multicast_hops

  def initialize addresses: [*IPV4, *IPV6], port: PORT
    @addresses = addresses
    @port      = port

    @client_sockets = []
    @multicast_hops = 1
    @server_sockets = []
  end

  def broadcast_addresses
    make_server_sockets if @server_sockets.empty?
    addresses = local_ipv4 + local_ipv6

    addresses.each do |address|
      type =
        case address.afamily
        when Socket::AF_INET  then 4
        when Socket::AF_INET6 then 6
        end

      message_ip, message_scope = address.ip_address.split '%'
      address_n = IPAddr.new(message_ip).hton

      message = [type, address_n].pack 'Ca*'

      @server_sockets.map do |socket|
        family, _, socket_address, = socket.addr

        next if family == 'AF_INET' and message_scope

        if message_scope and socket_address =~ /%/ then
          next unless $' == message_scope
        end

        socket.send message, 0
      end
    end
  end

  def listen_for_addresses
    @listen_threads = make_client_sockets.map do |socket|
      Thread.new do
        loop do
          message = socket.recv 17
          _, data = message.unpack 'Ca*'

          address =
            begin
              IPAddr.new_ntoh data
            rescue IPAddr::Error
            end

          p got: address
        end
      end
    end
  end

  def local_ipv4
    Socket.ip_address_list.select do |addr|
      not addr.ipv6? and not addr.ipv4_loopback?
    end
  end

  def local_ipv6
    Socket.ip_address_list.select do |addr|
      not addr.ipv4? and not addr.ipv6_loopback?
    end
  end

  def make_client_socket address, interface_address = nil, interface = nil
    addrinfo = Addrinfo.udp address, @port

    socket = Socket.new addrinfo.pfamily, addrinfo.socktype,
                        addrinfo.protocol

    if addrinfo.ipv4_multicast? or addrinfo.ipv6_multicast? then
      if Socket.const_defined? :SO_REUSEPORT then
        socket.setsockopt :SOCKET, :SO_REUSEPORT, true
      else
        socket.setsockopt :SOCKET, :SO_REUSEADDR, true
      end

      if addrinfo.ipv4_multicast? then
        interface_address = '0.0.0.0' if interface_address.nil?
        socket.bind Addrinfo.udp interface_address, @port

        mreq =
          IPAddr.new(addrinfo.ip_address).hton +
          IPAddr.new(interface_address).hton

        socket.setsockopt :IPPROTO_IP, :IP_ADD_MEMBERSHIP, mreq
      else
        interface_address = '::1' if interface_address.nil?
        socket.bind Addrinfo.udp interface_address, @port

        mreq =
          IPAddr.new(addrinfo.ip_address).hton +
          [interface].pack('I')

        socket.setsockopt :IPPROTO_IPV6, :IPV6_JOIN_GROUP, mreq
      end
    end

    UDPSocket.for_fd socket.fileno
  end

  def make_client_sockets
    sockets = @addresses.map do |address|
      make_client_socket(*address)
    end

    @client_sockets.concat sockets
  end

  def make_server_socket address, interface = nil # :nodoc:
    addrinfo = Addrinfo.udp address, @port

    socket = Socket.new addrinfo.pfamily, addrinfo.socktype, addrinfo.protocol

    if addrinfo.ipv4_multicast? then
      socket.setsockopt Socket::Option.ipv4_multicast_loop 1
      socket.setsockopt Socket::Option.ipv4_multicast_ttl @multicast_hops
    elsif addrinfo.ipv6_multicast? then
      socket.setsockopt :IPPROTO_IPV6, :IPV6_MULTICAST_LOOP, true
      socket.setsockopt :IPPROTO_IPV6, :IPV6_MULTICAST_HOPS,
                        [@multicast_hops].pack('I')
      socket.setsockopt :IPPROTO_IPV6, :IPV6_MULTICAST_IF,
                        [interface].pack('I')
    else
      socket.setsockopt :SOL_SOCKET, :SO_BROADCAST, true
    end

    socket.connect addrinfo

    UDPSocket.for_fd socket.fileno
  end

  def make_server_sockets
    sockets = @addresses.map do |address, _, interface|
      make_server_socket address, interface
    end

    @server_sockets.concat sockets
  end

end

