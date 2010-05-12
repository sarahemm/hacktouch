#!/usr/bin/env ruby

require 'rubygems'
require 'mq'
require 'json'
require 'log4r'
require 'log4r/configurator'
include Log4r

VLC = "/Applications/VLC.app/Contents/MacOS/VLC";
VLC_ARGS = "--intf=dummy --control=rc --rc-fake-tty";

class VLCControl
  def initialize
    begin
      # launch VLC and attach an I/O object to its remote control interface
      @vlc = IO.popen("#{VLC} #{VLC_ARGS} 2>/dev/null", "w+")
    rescue
      puts "error: #{$!}"
    end
  end
  
  def playlist_clear
    @vlc.puts("clear")
    get_retval
  end

  def pause
    @vlc.puts("pause")
    get_retval
  end
  
  def stop
    @vlc.puts("stop")
    get_retval
  end
  
  def play
    @vlc.puts("play")
    get_retval
  end
  
  def playlist_add(source)
  puts "@@@ PLAYING: #{source} @@@"
    @vlc.puts("add \"#{source}\"")
    get_retval
  end
  
  def playing?
    flush_input(@vlc)
    @vlc.puts("is_playing")
    get_plain_response
  end
  
  def now_playing
    flush_input(@vlc)
    @vlc.puts("get_title")
    get_plain_response.chomp!
  end

  def quit
    @vlc.puts("quit")
    get_retval
  end
  
  def flush_input(handle)
    # flush any input left in the buffer (non-blockingly, obviously)
    begin
      handle.read_nonblock(4096)
    rescue
    end
  end
  
  def get_plain_response
    # return a 'plain response' to a command, filtering out any status change messages.
    @vlc.readpartial(4096).each_line do |line|
      return line if line !~ /status change/;
    end
    ""
  end
  
  def get_retval
    re_retval     = /^\S+: returned (\d+)/;
    # capture any VLC output, then pick out the return value of the last command and discard anything else
    vlc_output = @vlc.readpartial(4096);
    re_match = re_retval.match(vlc_output);
    if(re_match) then
      return re_match[1];
    end
  end
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

Configurator.load_xml_file('log4r.xml')
log = Logger.get('hacktouch::backend::audiod')

AMQP.start(:host => 'localhost') do
  #AMQP.logging = true
  amq = MQ.new
  log.debug "Launching and connecting to VLC."
  vlc = VLCControl.new
  log.debug "VLC ready, subscribing to queue."
  amq.queue('hacktouch.audio.request').subscribe{ |header, msg|
    msg = JSON.parse(msg);
    log.debug "Command '#{msg['command']}' received on request queue."
    case msg['command']
      when 'queue' then
        if(msg['source']) then
          vlc.playlist_clear
          vlc.playlist_add(msg['source']);
          vlc.stop
          respond_with_success(header)
        else
          respond_with_error(header, "No audio source provided.")
          log.warn("Queue command received with no audio source")
        end        
      when 'play' then
        if(msg['source']) then
          vlc.playlist_clear
          vlc.playlist_add(msg['source']);
        else
          vlc.play
        end
        respond_with_success(header)
      when 'pause' then
        vlc.pause
        respond_with_success(header)
      when 'stop' then
        vlc.stop
        respond_with_success(header)
      when 'now_playing' then
        response_msg = Hash.new
        response_msg['now_playing'] = vlc.now_playing
        respond_to(header, response_msg)
      when 'status' then
        response_msg = Hash.new
        if(vlc.playing?) then
          response_msg['status'] = "playing";
        else
          response_msg['status'] = "stopped";
        end
        respond_to(header, response_msg);
    end
    log.debug "Command processing complete."
  }
end
