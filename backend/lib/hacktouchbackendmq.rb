require 'json'

class HacktouchBackendMessage
  def initialize(header, msg)
    @header = header
    @raw_msg = msg
    @msg = JSON.parse(msg)
  end
  
  def [](msg_field)
    @msg[msg_field]
  end

  def respond_with_success(response_msg = Hash.new)
    response_msg['result'] = 'success'
    MQ.new.queue(@header.properties[:reply_to], :auto_delete => true).publish(response_msg.to_json)
  end

  def respond_with_error(error, response_msg = Hash.new)
    response_msg['result'] = 'error'
    response_msg['error'] = error
    MQ.new.queue(@header.properties[:reply_to], :auto_delete => true).publish(response_msg.to_json)
  end
end
