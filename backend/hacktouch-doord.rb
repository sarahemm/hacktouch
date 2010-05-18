#!/usr/bin/env ruby

require 'rubygems'
require 'mq'
require 'json'
require 'sequel'
require 'yaml'
require 'log4r'
require 'log4r/configurator'
require 'lib/hacktouchbackendmq'
include Log4r

Configurator.load_xml_file('log4r.xml')
@log = Logger.get('hacktouch::backend::doord')

config = YAML::load(File.read('hacktouch_config.yaml'))
doorconfig = config['door']
dburl = "mysql://#{doorconfig['username']}:#{doorconfig['password']}@#{doorconfig['server']}/#{doorconfig['database']}"

@log.debug "Connecting to door system database at #{dburl}."
db = Sequel.connect(dburl)
AMQP.start(:host => 'localhost') do
  amq = MQ.new
  @log.debug "Connected to door system, ready for requests."
  amq.queue('hacktouch.door.request').subscribe{ |header, msg|
    msg = HacktouchBackendMessage.new(header, msg);
    case msg['command']
      when 'recent' then
        msg['entries'] = 10 if !msg.has_key? 'entries'
        msg['entries'] = 100 if msg['entries'] > 100
        response_msg = Hash.new
        response_msg['entries'] = []
        @log.debug "Retrieving the most recent #{msg['entries']} door entries from the database."
        db[:access_log].join(:card, :card_id => :card_id).reverse_order(:logged).limit(msg['entries']).each do |entry|
          entry_hash = Hash.new
          entry_hash['time'] = entry[:logged]
          entry_hash['name'] = entry[:nick]
          response_msg['entries'].push(entry_hash)
        end
        @log.debug "Replying to #{header.properties[:reply_to]} with #{msg['entries']} recent door entries."
        msg.respond_with_success response_msg
    end
  }
end
