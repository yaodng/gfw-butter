#! /usr/bin/env ruby

require 'cidr-lite'
require 'json'
require 'open-uri'
require 'resolv'

blocked  = JSON.parse File.read("#{__dir__}/blocked.json")
data_dir = "#{__dir__}/data"
ranges   = {}

def addr_merge(ranges)
  merger = CIDR::Lite.new
  ranges.each { |i| merger.add i }
  merger.list
end

# -------------------------------------------------------------------
# Collect IP ranges
# -------------------------------------------------------------------
ranges['cloudflare'] = open(blocked['ip_ranges']['cloudflare']).read.split("\n")
ranges['aws']        = JSON.parse(open(blocked['ip_ranges']['aws']).read)['prefixes']
  .select{ |p| p['service'] == 'AMAZON' && !p['region'].start_with?('cn-') }
  .map{ |p| p['ip_prefix'] }

blocked['networks'].each do |k, v|
  ranges[k] = addr_merge Array(v).map {|n|
    `whois -h whois.radb.net -- '-i origin #{n}'`.split("\n").grep(/^route:/).map { |i| i.split(/\s+/).last }
  }.flatten
end

# -------------------------------------------------------------------
# Fetch IPs of blocked domains
# -------------------------------------------------------------------
open_dns   = ['208.67.222.222', 443]
dns_server = Resolv::DNS.new nameserver_port: [open_dns]
hosts      = Hash[ blocked['domains'].map{ |d| [d, dns_server.getaddress(d).to_s] } ]
File.write "#{data_dir}/hosts.json", JSON.pretty_generate(hosts)

# -------------------------------------------------------------------
# Store IP ranges
# -------------------------------------------------------------------
ranges.each do |k, v|
  # save by name for human
  File.write "#{data_dir}/ip_ranges/#{k}.json", JSON.pretty_generate(v)
end

# save combined file for configuration generation
ranges['hosts'] = hosts.values
File.write "#{data_dir}/ip_ranges.json", JSON.pretty_generate(addr_merge ranges.values.flatten)
