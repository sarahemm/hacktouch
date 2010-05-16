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
@log = Logger.get('hacktouch::backend::weatherd')

def feed_list
  db = Sequel.connect('sqlite://hacktouch.sqlite3')
  stream_list = Array.new
  db[:news_feeds].order(:name).each do |stream|
    stream_list.push(stream[:url]);
  end
  
  stream_list
end

def refresh_sites
  @log.info "Beginning refresh of available sites."
  
  xml = ""
  open("http://dd.weatheroffice.ec.gc.ca/citypage_weather/xml/siteList.xml") do |s| xml = s.read end
  doc = REXML::Document.new xml
  sites = Hash.new
  doc.elements.each("siteList/site")  do |site|
    siteCity = site.elements["nameEn"].text
    siteProvince = site.elements["provinceCode"].text
    siteID = site.attributes["code"]
    sites["#{siteProvince}/#{siteCity}"] = "#{siteProvince}/#{siteID}"
  end
  
  @log.info "Site refresh complete."
  sites
end

sites = refresh_sites
siteConditions = Hash.new

AMQP.start(:host => 'localhost') do
  amq = MQ.new
  amq.queue('hacktouch.weather.request').subscribe{ |header, msg|
    msg = HacktouchBackendMessage.new(header, msg);
    case msg['command']
      when 'current' then
        requested_site = "#{msg['province'].upcase}/#{msg['city'].capitalize}"
        if((!siteConditions.has_key? requested_site) || siteConditions[requested_site]["last_refresh"] < Time.now.to_i - 15*60) then
          @log.info "Fetching weather for #{requested_site}"
          xml = ""
          open("http://dd.weatheroffice.ec.gc.ca/citypage_weather/xml/#{sites[requested_site]}_e.xml") do |s| xml = s.read end
          doc = REXML::Document.new xml
          current = doc.elements["siteData/currentConditions"]
          siteConditions[requested_site] = Hash.new
          siteConditions[requested_site]["last_refresh"] = Time.now.to_i
          siteConditions[requested_site]["temperature"] = current.elements["temperature"].text
          siteConditions[requested_site]["humidity"] = current.elements["relativeHumidity"].text
          siteConditions[requested_site]["wind_speed"] = current.elements["wind/speed"].text
          siteConditions[requested_site]["wind_direction"] = current.elements["wind/direction"].text
          siteConditions[requested_site]["icon_code"] = current.elements["iconCode"].text
          siteConditions[requested_site]["conditions"] = current.elements["condition"].text
        else
          @log.debug "Using previously cached weather data for #{requested_site}"
        end
        response_msg = Hash.new
        response_msg.merge!(siteConditions[requested_site])
        @log.debug "Replying to #{header.properties[:reply_to]} with weather for #{requested_site}"
        msg.respond_with_success response_msg
    end
  }
end
