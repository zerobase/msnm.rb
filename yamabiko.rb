#!/usr/local/bin/ruby -wKs

=begin

= yamabiko.rb version 0.1.0  2001/11/30 - 2002/11/28

Copyright (c) 2001 2002  msnm@zerobase.jp

This program is free software. You can re-distribute and/or
modify this program under the same terms as Ruby itself,
Ruby Distribute License or GNU General Public License.

== What is This?

search quoted words

=end


require 'msnm'


class YamabikoSessionHandler < Net::InstantMessaging::MSNMessenger::SessionHandler

  def handle_message( peer_id, peer_nick, msg_header, msg_body )
    if msg_header =~ /\r\nContent-Type: text\/plain/um
      queue_message(msg_body)  # echo ( output as same as input )
    end
  end

  def on_join( peer_id, peer_nick )
    queue_message( 'hello ' + peer_id )
  end

end


class YamabikoSessionHandlerFactory

  def create( msnm, session )
    YamabikoSessionHandler.new( msnm, session )
  end

end



if __FILE__ == $0


  USERID = '***@hotmail.com'      # account for an IM agent
  PASSWD = '***'                  # password


  # start logging

  logfile = $stdout
  Net::InstantMessaging::MSNMessenger::ProtocolHandler.logfile = logfile
  now = Time.now
  process_tag = now.strftime('%Y%m%d%H%M%S') + now.usec.to_s
  logfile << "process start #{process_tag}\n"


  # initialize service

  msnm = Net::InstantMessaging::MSNMessenger.new( USERID, PASSWD,
                                     YamabikoSessionHandlerFactory.new )
  msnm.ns.synchronize
  msnm.ns.privacy_mode :BLP_ALLOW


  # start service

  msnm.ns.online
  msnm.listen     # -> listening...
  msnm.logout


  # finish logging

  logfile << "process finish #{process_tag}\n"


end
