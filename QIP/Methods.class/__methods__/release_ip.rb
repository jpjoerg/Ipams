#
# Description: 
# 
# Get IP from Vital QIP
#
$evm.log("info", "LOG99 ReleaseIP: ############################## QIP request start ##############################")
prov = $evm.root['miq_provision'] || \
        $evm.root['vm'].miq_provision
require 'rest-client'
require 'json'
require 'ipaddr'
require 'nokogiri'
require 'base64'
@debug = true

##############################
# Call Host
##############################
$evm.log("info", "LOG99 - ReleaseIP: ############################## Call Host ##############################") if @debug
def call_host(action, ref, body_hash=nil)
  begin
    # url example to provide:  url: "https://qip.prodsrz.srzintra.de:743/api/v1/{{ qip_organization }}/v4subnet.json?name={{ qip_customer_domain_name }}"
    url = "https://" + @server + ":" + @port + "/api/v1/" + @organization + "/" + "#{ref}"

    $evm.log("info", "LOG99 - ReleaseIP Call_host: ############################## URL: #{url}, Action: #{action} ") if @debug

    params = {
    :method => action,
    :url => url,
    :verify_ssl => false,
    :headers => { 
      :Authentication => "Basic #{@username}:#{@password}",
      :accept => :json, 
      :content_type => :json }
      }
    
    params[:payload] = JSON.parse(body_hash) if body_hash
  
    $evm.log("info", "LOG99 - ReleaseIP Call_host: ############################## Response: #{params}") if @debug

    response = RestClient::Request.execute(params)
    $evm.log("info", "LOG99 - ReleaseIP Call_host: ############################## Response: #{response}") if @debug

    unless response.code == 200 || response.code == 201
      raise "Host failure response: <#{response.code}>"
      else
      $evm.log("info", "LOG99 - ReleaseIP Call_host: ############################## Success response:<#{response.code}> from: <#{response.request.url}") if @debug
    end
    return response rescue(return response)
  rescue RestClient::BadRequest => badrequest
    raise "ReleaseIP Bad request: #{badrequest} url: #{url} or possible wrong API version!"
  end
end


##############################
# Write Ipam 
##############################
def release_ip(ipaddr)
  begin
    query_string = "v4address/#{ipaddr}/"
    results = call_host(:delete, query_string)
    $evm.log("info", "LOG99 - ReleaseIP write_IPAM: ############################## results: #{results}, Query string: #{query_string}") if @debug    
  end   
end

#######################################################################
############################### Main Section ##########################
#######################################################################
@username = $evm.object['username']
@password = $evm.object.decrypt('password')
@server = $evm.object['hostname']
@port = $evm.object['port']
@organization = $evm.object['organization']  # This value is static as only 1 organization exist but could be a variable provided by dialog
$evm.log("info", "LOG99 - ReleaseIP - Main: ########################## ReleaseIP auth :username: <#{@username}>,password: <#{@password}>,server: <#{@server}>, organization: <#{@organization}>")  if @debug 

ipaddr = prov.get_option(:ip_addr)
$evm.log("info", "LOG99 - ReleaseIP IP: ############################## IP: #{ipaddr}") if @debug    
releaseIP = release_ip(ipaddr)

$evm.log("info", "LOG99 - ReleaseIP: ############################## ReleaseIP request End ##############################")
## $evm.log("info", "CUSTOMIZE REQUEST : rhv_env = #{toto} ") if @debug 

exit MIQ_OK
