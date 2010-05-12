require 'json'

class TimeoutException < RuntimeError
  def initialize()
  end
end

class HacktouchMQ
  def self.mq_request(request_queue, request_msg)
    if(!request_queue || request_queue == "") then
      response_msg = Hash.new
      response_msg['result'] = 'error'
      response_msg['error'] = 'No request queue specified.'
      return response_msg
    end
    response_queue = request_queue.gsub(/request$/, "") + "response.#{rand(999999)}"
    request_q = Carrot.queue(request_queue)
    response_q = Carrot.queue(response_queue)
    
    request_q.publish(request_msg.to_json, :reply_to => response_queue)
    start_time = Time.now
    until (response_msg = response_q.pop()) || Time.now - start_time > 10
    end
    if !response_msg then
      raise TimeoutException
    end
    response_q.ack
    return JSON.parse(response_msg)
  end
end
