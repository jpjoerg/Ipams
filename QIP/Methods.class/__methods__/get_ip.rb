#
# Description: 
# 
# Get IP from Vital QIP
#
$evm.log("info", "LOG99 : ############################## QIP request start ##############################")
prov = $evm.root['miq_provision_request'] || \
        $evm.root['miq_provision'] || \
        $evm.root['miq_provision_request_template']
require 'rest-client'
require 'json'
require 'ipaddr'
require 'nokogiri'
require 'base64'
@debug = false

##############################
# Call Host
##############################
$evm.log("info", "LOG99 - GetIP: ############################## Call Host ##############################") if @debug
def call_host(action, ref, body_hash=nil)
  begin
    # url example to provide:  url: "https://qip.prodsrz.srzintra.de:743/api/v1/{{ qip_organization }}/v4subnet.json?name={{ qip_customer_domain_name }}"
    url = "https://" + @server + ":" + @port + "/api/v1/" + @organization + "/" + "#{ref}"

    $evm.log("info", "LOG99 - GetIP Call_host: ############################## URL: #{url}, Action: #{action} ") if @debug
    #response = RestClient::Request.new(method: action, url: url, verify_ssl: false, headers: { Authentication: "Basic #{@username}:#{@password}", content_type: 'application/json', accept: :json}).execute
    params = {
      :method => action,
      :url => url,
      :verify_ssl => false,
      :headers => {
        :Authentication => "Basic #{@username}:#{@password}",
        :content_type => :json,
        :accept => :json}
    }

    params[:payload] = body_hash if body_hash
    $evm.log("info", "LOG99 - GetIP Call_host: ############################## Response: #{params}") if @debug

    response = RestClient::Request.execute(params)
    $evm.log("info", "LOG99 - GetIP Call_host: ############################## Response: #{response}") if @debug

    unless response.code == 200 || response.code == 201
      raise "Host failure response: <#{response.code}>"
      else
      $evm.log("info", "LOG99 - GetIP Call_host: ############################## Success response:<#{response.code}> from: <#{response.request.url}") if @debug
    end
    return response rescue(return response)
  rescue RestClient::BadRequest => badrequest
    raise "GetIP Bad request: #{badrequest} url: #{url} or possible wrong API version!"
  end
end

##############################
# Get subnets 
##############################
def get_subnet(prefixsubnet)
  begin
    # Add a '*' at end of string in place of VLAN name that is not existing yet
    # This Vlan name is included in the Subnetname even if not existing as a VLAN in QIP
    query_string = "v4subnet.json?name=#{prefixsubnet}*"
    response = call_host(:get, query_string)
    results = JSON.parse(response)
    $evm.log("info", "LOG99 - GetIP get_subnet: ############################## results: #{results}, Query string: #{query_string}") if @debug
    subnets = Array.new
    results['list'].each do |item|
      subnets << item['subnetAddress']
      $evm.log("info", "LOG999 - GetIP Subnet:########################## Subnet information :<#{item}> - Subnets: <#{subnets}>") if @debug
    end
    return subnets
  end   
end

##############################
# IP reservation 
##############################
def next_ip(subnets)
  begin
    ip = nil
    if ip.blank? 
      subnets.each do |subnet|
        query_string = "selectedv4address/#{subnet}.json"
        response = call_host(:put, query_string)
        results = JSON.parse(response)
        $evm.log("info", "LOG99 - GetIP get_nextip: ############################## results: #{results}, Query string: #{query_string}") if @debug
        results.each do |k,v|
          $evm.log("info", "LOG999 - GetIP next_ip:########################## IP information :key <#{k}>, value <#{v}>") if @debug
          unless k =~ /error/
            ip = v
            $evm.log("info", "LOG999 - GetIP next_ip:########################## IP information :<#{ip}>") if @debug
            # Get CIDR
            get_cidr(subnet)
            return ip
          end
        end
      end
    end
  end
end

##############################
# Get Netmask and convert to CIDR for cloudinit 
##############################
def get_cidr(subnet)
  begin
    query_string = "v4subnet.json?address=#{subnet}"
    response = call_host(:get, query_string)
    results = JSON.parse(response)
    $evm.log("info", "LOG99 - GetIP CIDR: ############################## results: #{results}, Query string: #{query_string}") if @debug
    dns_servers = Array.new
    results['list'].each do |item|
      mask = item['subnetMask']
      @gateway = item['defaultRouters']['name'].join
      @network = item['subnetName']
      @bitmask = IPAddr.new(mask).to_i.to_s(2).count("1")
      preferred_dns = item['preferredDNSServers']
      preferred_dns['name'].each do |dns|
        dns_servers << IPSocket.getaddress(dns)
      end
      @dns_servers = dns_servers.join(",")
      $evm.log("info", "LOG999 - GetIP CIDR:########### Mask information:<#{item}>-Mask:<#{@bitmask}>-Gateway:<#{@gateway}>-Network:<#{@network}> - DNS-Servers:<#{@dns_servers}") if @debug
      $evm.log("info", "LOG999 - GetIP CIDR:########################## Cidr information: <#{@bitmask}>") if @debug
     end
  end
end

##############################
# Write Ipam 
##############################
def register_ip(ipaddr,vmname,domain)
  begin
    body = {
      :objectAddr => "#{@nextIP}",
      :objectDesc => "Done by CloudForms #{vmname} ",
      :domainName => "#{domain}",
      :objectName => "#{vmname}"
      }.to_json
    $evm.log("info", "LOG99 - GetIP Register IP: ############################## Body: #{body}") if @debug    

    query_string = "v4address"
    results = call_host(:put, query_string, body)

    $evm.log("info", "LOG99 - GetIP write_IPAM: ############################## results: #{results}, Query string: #{query_string}") if @debug    
  end   
end

############################### Main Section ##########################
@username = $evm.object['username']
@password = $evm.object.decrypt('password')
@server = $evm.object['hostname']
@port = $evm.object['port']
@organization = $evm.object['organization']  # This value is static as only 1 organization exist but could be a variable provided by dialog
$evm.log("info", "LOG99 - GetIP - Main: ########################## GetIP auth :username: <#{@username}>,password: <#{@password}>,server: <#{@server}>, organization: <#{@organization}>")  if @debug 
prefix = 'Cloudforms-'
@domain = prov.get_option(:dns_domain)
@prefixsubnet = prefix + @domain
@hostname = prov.get_option(:hostname)
@vmname = prov.get_option(:vm_name).split('.',0)[0]
$evm.log("info", "GetIP-Main:############################## domain: <#{@domain}>, prefixsubnet: #{@prefixsubnet}, name: <#{@vmname}>, hostname: <#{@hostname}>") if @debug

subnets = get_subnet(@prefixsubnet)
$evm.log("info", "GetIP-Main:############################## subnets:=> <#{subnets}>") if @debug

@nextIP = next_ip(subnets)
$evm.log("info", "GetIP-Main:############################## nextIP: <#{@nextIP}>") if @debug

registerIP = register_ip(@nextIP,@vmname,@domain)
$evm.log("info", "RegisterIP-Main:############################## nextIP: <#{registerIP}>") if @debug
default_vlan = "#{@network} (#{@network})"
# Set VM values
$evm.log("info", "Get-IP- :############################## Start VM value setting############################## ") if @debug
prov.set_option(:addr_mode, ["static", "static"])
prov.set_option(:ip_addr, "#{@nextIP}")
prov.set_option(:subnet_mask, "#{@bitmask}")
prov.set_option(:vm_name, "#{@vmname}")
prov.set_option(:dns_domain, "#{@domain}")
prov.set_option(:vm_target_name, "#{@vmname}")
prov.set_option(:vm_target_hostname, @vmname)
prov.set_option(:linux_host_name, "#{@vmname}")
prov.set_option(:gateway, @gateway)
prov.set_option(:dns_servers, "#{@dns_servers}")
prov.set_option(:dns_suffixes, "#{@domain}")
prov.set_vlan(default_vlan)
$evm.log("info", "Get-IP- :############################## VM values ############################## ") if @debug
$evm.log("info", "Get-IP-Values: addr_mode=#{@nextIP}, :subnet_mask=#{@bitmask}, :vm_name=#{@vmname}, :dns_domain=#{@domain}, :vm_target_name=#{@vmname}")
$evm.log("info", "Get-IP-Values: vm_target_hostname=#{@vmname}, :linux_host_name=#{@vmname}, :gateway=#{@gateway}, :vlan=#{default_vlan}")
$evm.log("info", "Get-IP-Values: dns_servers=#{@dns_servers},:dns_suffixes=#{@domain}")
$evm.log("info", "Get-IP- :############################## End VM value setting############################## ") if @debug
$evm.log("info", "LOG99 - GetIP: ############################## GetIP Name request End ##############################")
## $evm.log("info", "CUSTOMIZE REQUEST : rhv_env = #{toto} ") if @debug 

exit MIQ_OK
