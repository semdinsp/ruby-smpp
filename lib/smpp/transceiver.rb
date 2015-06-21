# encoding: UTF-8

# The SMPP Transceiver maintains a bidirectional connection to an SMSC.
# Provide a config hash with connection options to get started.
# See the sample_gateway.rb for examples of config values.
# The transceiver accepts a delegate object that may implement
# the following (all optional) methods:
#
#   mo_received(transceiver, pdu)
#   delivery_report_received(transceiver, pdu)
#   message_accepted(transceiver, mt_message_id, pdu)
#   message_rejected(transceiver, mt_message_id, pdu)
#   bound(transceiver)
#   unbound(transceiver)

class Smpp::Transceiver < Smpp::Base

  # Send an MT SMS message. Delegate will receive message_accepted callback when SMSC
  # acknowledges, or the message_rejected callback upon error
  def send_mt(message_id, source_addr, destination_addr, short_message, options={})
    logger.debug "Sending MT: #{short_message}"
    if @state == :bound
      pdu = Pdu::SubmitSm.new(source_addr, destination_addr, short_message, options)
      write_pdu pdu

      # keep the message ID so we can associate the SMSC message ID with our message
      # when the response arrives.
      @ack_ids[pdu.sequence_number] = message_id
    else
      raise InvalidStateException, "Transceiver is unbound. Cannot send MT messages."
    end
  end

  # Send a concatenated message with a body of > 160 characters as multiple messages.
  def send_concat_mt(message_id, source_addr, destination_addr, message, options = {})
    logger.debug "Sending concatenated MT: #{message}"
    if @state == :bound
      # Split the message into parts of 153 characters. (160 - 7 characters for UDH)
      parts = []
      while message.size > 0 do
        parts << message.slice!(0..Smpp::Transceiver.get_message_part_size(options))
      end

      0.upto(parts.size-1) do |i|
      #  udh = [ 5,         # UDH is 5 bytes.
      #         0, 3,       # This is a concatenated message
      #         message_id.to_i%256, # Ensure single byte message_id
       #        parts.size, # How many parts this message consists of
      #         i+1         # This is part i+1
      #        ].pack('C'*6)
        udh = [ 6,         # UDH is 5 bytes.
             0, 8,       # This is a concatenated message
             0, message_id.to_i%256, # Ensure single byte message_id
               parts.size, # How many parts this message consists of
               i+1         # This is part i+1
                ].pack('C'*7)

        options[:esm_class] = 64 # This message contains a UDH header.
        options[:udh] = udh
        puts  "SCOTT SEND CONCAT #{udh} parts size: #{parts.size}  id int:  id: #{message_id.to_i}id: #{message_id.to_i%256}"

        pdu = Pdu::SubmitSm.new(source_addr, destination_addr, parts[i], options)
        write_pdu pdu

        # This is definately a bit hacky - multiple PDUs are being associated with a single
        # message_id.
        @ack_ids[pdu.sequence_number] = message_id
      end
    else
      raise InvalidStateException, "Transceiver is unbound. Connot send MT messages."
    end
  end

  # Send  MT SMS message for multiple dest_address
  # Author: Abhishek Parolkar (abhishek[at]parolkar.com)
  # USAGE: $tx.send_multi_mt(123, "9100000000", ["9199000000000","91990000000001","9199000000002"], "Message here")
  def send_multi_mt(message_id, source_addr, destination_addr_arr, short_message, options={})
    logger.debug "Sending Multiple MT: #{short_message}"
    if @state == :bound
      pdu = Pdu::SubmitMulti.new(source_addr, destination_addr_arr, short_message, options)
      write_pdu pdu

      # keep the message ID so we can associate the SMSC message ID with our message
      # when the response arrives.
      @ack_ids[pdu.sequence_number] = message_id
    else
      raise InvalidStateException, "Transceiver is unbound. Cannot send MT messages."
    end
  end

  # Send BindTransceiverResponse PDU.
  def send_bind
    raise IOError, 'Receiver already bound.' unless unbound?
    pdu = Pdu::BindTransceiver.new(
        @config[:system_id],
        @config[:password],
        @config[:system_type],
        @config[:source_ton],
        @config[:source_npi],
        @config[:source_address_range])
    write_pdu(pdu)
  end

  # Use data_coding to find out what message part size we can use
  # http://en.wikipedia.org/wiki/SMS#Message_size
  def self.get_message_part_size options
    return 152 if options[:data_coding].nil?
    return 152 if options[:data_coding] == 0
    return 134 if options[:data_coding] == 3
    return 134 if options[:data_coding] == 5
    return 134 if options[:data_coding] == 6
    return 134 if options[:data_coding] == 7
    return 67  if options[:data_coding] == 8
    return 152
  end
end
