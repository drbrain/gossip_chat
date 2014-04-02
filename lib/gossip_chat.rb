require 'ipaddr'
require 'socket'

class GossipChat
  VERSION = '1.0'

  IPV4 = %w[239.71.79.83 0.0.0.0]
  PORT = 7380

  def self.first_nonlocal_ifindex
    Socket.getifaddrs.select do |addr|
      addr.addr.pfamily == Socket::PF_LINK
    end.find do |addr|
      mac, = addr.addr.getnameinfo
      !mac.empty?
    end.ifindex
  end

  INTERFACE = first_nonlocal_ifindex

  IPV6 = ['ff02::e74f:5353', '::1', INTERFACE]

  attr_accessor :multicast_hops

  def initialize addresses: [IPV4, IPV6], port: PORT
    @addresses = addresses
    @port      = port

    @client_sockets = []
    @multicast_hops = 0
    @server_sockets = []
  end

  def local_ipv4
    addrinfo = Socket.ip_address_list.find do |addr|
      not addr.ipv6? and not addr.ipv4_loopback?
    end

    return unless addrinfo

    addrinfo.ip_address
  end

  def local_ipv6
    addrinfo = Socket.ip_address_list.find do |addr|
      not addr.ipv4? and not addr.ipv6_loopback? and
        not addr.ipv6_linklocal? and not addr.ipv6_unique_local?
    end

    return unless addrinfo

    addrinfo.ip_address
  end

  def make_client_socket address, interface_address = nil, interface = nil
    interface ||= INTERFACE
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
    else
      socket.bind addrinfo
    end

    socket
  end

  def make_client_sockets
    sockets = @address.map do |address|
      make_client_socket(*address)
    end

    @client_sockets.concat sockets
  end

  def make_server_socket address, interface # :nodoc:
    interface ||= INTERFACE

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

    socket
  end

  def make_server_sockets
    sockets = @address.map do |address, _, interface|
      make_server_socket address, interface
    end

    @server_sockets.concat sockets
  end

end

