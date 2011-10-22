#!/usr/bin/env ruby

require 'rubygems'
require 'rss/1.0'
require 'rss/2.0'
require 'open-uri'
require 'mq'
require 'json'
require 'sequel'
require 'log4r'
require 'log4r/configurator'
require 'lib/hacktouchbackendmq'
require "rexml/document"
include REXML
include Log4r

Configurator.load_xml_file('log4r.xml')
@log = Logger.get('hacktouch::backend::streetcar')

arrival_times = Hash.new
dirs = ['dir1','dir2']

@log.debug "Streetcar starting up"
AMQP.start(:host => 'localhost') do
  amq = MQ.new
  amq.queue('hacktouch.streetcar.request').subscribe{ |header, msg|
    msg = HacktouchBackendMessage.new(header, msg)
    case msg['command']
      when 'next' then
        if((!arrival_times.has_key? msg['stop']) || arrival_times[msg['stop']]["last_refresh"] < Time.now.to_i - 45) then
          arrival_times[msg['stop']] = Hash.new
          arrival_times[msg['stop']]["last_refresh"] = Time.now.to_i
          dirs.each do |dir|
            @log.debug "Fetching arrival data for #{msg['stop']} #{dir}"
            xml = ""
            @log.debug xml
            open("http://webservices.nextbus.com/service/publicXMLFeed?command=predictions&a=ttc&s=#{msg[dir]}&r=#{msg['route']}") do |s| xml = s.read end
            doc = REXML::Document.new xml
            arrival_times[msg['stop']][dir] = doc.elements['body/predictions/direction/prediction#minutes'].attributes['minutes']
            end
          else
            @log.debug "Using previously cached location data for #{msg['stop']}"
          end
        response_msg = Hash.new
        response_msg.merge!(arrival_times[msg['stop']])
        @log.debug "Replying to #{header.properties[:reply_to]} with streetcar predictions for #{msg['stop']}"
        msg.respond_with_success response_msg
    end
  }
end
