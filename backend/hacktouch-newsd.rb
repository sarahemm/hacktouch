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
include Log4r

Configurator.load_xml_file('log4r.xml')
@log = Logger.get('hacktouch::backend::newsd')

def feed_list
  db = Sequel.connect('sqlite://hacktouch.sqlite3')
  stream_list = Array.new
  db[:news_feeds].order(:name).each do |stream|
    stream_list.push(stream[:url]);
  end
  
  stream_list
end

def refresh_feeds
  @log.info "Beginning refresh of news feeds."
  
  feeds = []
  feed_list.each do |source|
    content = ""
    @log.debug "Refreshing #{source}"
    open(source) do |s| content = s.read end
    feeds.push(RSS::Parser.parse(content, false))
  end
  @log.info "News feed refresh complete."
  feeds
end

def respond_to(header, response_msg)
  response_msg['result'] = 'success'
  MQ.new.queue(header.properties[:reply_to], :auto_delete => true).publish(response_msg.to_json)
end

def respond_with_success(header)
  response_msg = Hash.new
  response_msg['result'] = 'success'
  MQ.new.queue(header.properties[:reply_to], :auto_delete => true).publish(response_msg.to_json)
end

def respond_with_error(header, error)
  response_msg = Hash.new
  response_msg['result'] = 'error'
  response_msg['error'] = error
  MQ.new.queue(header.properties[:reply_to], :auto_delete => true).publish(response_msg.to_json)
end

feeds = refresh_feeds

AMQP.start(:host => 'localhost') do
  EM.add_periodic_timer(15*60) {
    feeds = refresh_feeds
  }
  
  amq = MQ.new
  amq.queue('hacktouch.news.request').subscribe{ |header, msg|
    msg = JSON.parse(msg);
    case msg['command']
      when 'get' then
        rss = feeds[rand(feeds.length)]
        msg = Hash.new
        msg['source'] = rss.channel.title
        randomItem = rand(rss.items.length)
        msg['title'] = rss.items[randomItem].title
        msg['content'] = rss.items[randomItem].description.split("at Slashdot.")[0]
        @log.debug "replying to #{header.properties[:reply_to]} with an article from #{msg['source']}"
        respond_to(header, msg)
    end
  }
end
