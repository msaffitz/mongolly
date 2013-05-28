require 'aws-sdk'
require 'socket'
require 'ipaddress'

class AWS::EC2::InstanceCollection

    def find_from_address(address, port = 27107)
      ip_address = convert_address_to_ip(address, port)

      instances = select do |instance|
        instance.public_ip_address == ip_address || instance.private_ip_address == ip_address
      end
      raise error_class "InstanceNotFound"  if instances.length != 1

      return instances.first
    rescue SocketError
      raise RuntimeError.new("Unable to determine IP address from #{address}:#{port}")
    end

private
  def convert_address_to_ip(address, port)
    return address if ::IPAddress.valid? address

    ip_addresses = ::Addrinfo.getaddrinfo(address, port, nil, :STREAM)
    raise error_class "MultipleIpAddressFound"  if ip_addresses.length > 1

    return ip_addresses[0].ip_address
  end

end
