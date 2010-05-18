#!/usr/bin/env ruby

require 'rubygems'
require 'sinatra'
require 'carrot'
require 'sinatra/static_assets'
require 'haml'
require 'sass'
require 'sequel'
require 'lib/partials.rb'
require 'lib/hacktouchmq.rb'
gem 'sinatra-static-assets'
helpers Sinatra::Partials

template :layout do
  "!!! XML\n!!!\n%html\n  %head\n    = stylesheet_link_tag 'main.css'\n  %body\n    =yield\n"
end

get '/main.css' do
    content_type 'text/css', :charset => 'utf-8'
    sass :main
end
  
get '/' do
  haml :index
end

get '/now_playing' do
  msg = Hash.new
  msg['command'] = 'now_playing'
  response_msg = HacktouchMQ.mq_request("hacktouch.audio.request", msg)
  response_msg['now_playing']
end

post '/now_playing' do
  msg = Hash.new
  msg['command'] = 'play'
  msg['source'] = params[:source]
  Carrot.queue("hacktouch.audio.request").publish(msg.to_json)
end

delete '/now_playing' do
  msg = Hash.new
  msg['command'] = 'stop'
  Carrot.queue('hacktouch.audio.request').publish(msg.to_json)
end

get '/audio_streams' do
  content_type :json
  
  DB = Sequel.connect('sqlite://hacktouch.sqlite3')
  stream_list = Array.new
  DB[:audio_streams].order(:name).each do |stream|
    stream_list.push({'name' => stream[:name], 'url' => stream[:url]})
  end
  stream_list.to_json
end

get '/news' do
  content_type :json
  
  msg = Hash.new
  msg['command'] = 'get'
  begin
    response_msg = HacktouchMQ.mq_request("hacktouch.news.request", msg)
  rescue TimeoutException
    halt 504, {'Content-Type' => 'text/plain'}, 'Request to news backend timed out.'
  end
  "#{response_msg.to_json}"
end

get '/weather' do
  content_type :json
  
  msg = Hash.new
  msg['command'] = 'current'
  msg['province'] = "ON"
  msg['city'] = "Toronto"
  begin
    response_msg = HacktouchMQ.mq_request("hacktouch.weather.request", msg)
  rescue TimeoutException
    halt 504, {'Content-Type' => 'text/plain'}, 'Request to weather backend timed out.'
  end
  "#{response_msg.to_json}"
end

get '/recent_visitors' do
  content_type :json
  
  msg = Hash.new
  msg['command'] = 'recent'
  msg['entries'] = 5
  begin
    response_msg = HacktouchMQ.mq_request("hacktouch.door.request", msg)
  rescue TimeoutException
    halt 504, {'Content-Type' => 'text/plain'}, 'Request to door system backend timed out.'
  end
  # add how many minutes ago it was, to make the frontend easier to deal with
  response_msg['entries'].each do |entry|
    entry['mins_ago'] = (Time.new - Time.parse(entry['time'])).to_i / 60
  end
  
  "#{response_msg.to_json}"
end