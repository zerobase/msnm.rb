#!/usr/local/bin/ruby -wKs

=begin

= kotosaka.rb version 0.2.0  2001/11/21 - 2002/11/28

Copyright (c) 2001 2002  msnm@zerobase.jp

This program is free software. You can re-distribute and/or
modify this program under the same terms as Ruby itself,
Ruby Distribute License or GNU General Public License.

== What is This?

search quoted words

=end


require 'msnm'


class KotosakaSessionHandler < Net::InstantMessaging::MSNMessenger::SessionHandler

  EMOTICONS = %w_ (Y) (y) (N) (n) (B) (b) (D) (d) (X) (x) (Z) (z) :-[ :[ (}) ({)
                  :-) :) :-D :D :d :-O :o :-P :p ;-) ;) :-( :( :-S :s :-| :| :'(
                  :$ :-$ (H) (h) :-@ :@ (A) (a) (6) (L) (l) (U) (u) (K) (k)
                  (G) (g) (F) (f) (W) (w) (P) (p) (~) (T) (t) (@) (&) (C) (c)
                  (I) (i) (S) (*) (8) (E) (e) (^) (O) (o) (T) (t) (M) (m) _

  def handle_message( peer_id, peer_nick, msg_header, msg_body )
    msg_body = msg_body.dup
    if msg_header =~ /\r\nContent-Type: text\/plain/um
      if msg_body =~ /\w+/um
        EMOTICONS.each do |emo|
          msg_body.gsub!( Regexp.new( Regexp.quote(emo), Regexp::MULTILINE, 'UTF-8'),
                          emo.split(//u).reverse.join('') )
        end
        msg_body.split(/\r\n/u).collect { |line|
          msg = line.split(//u).reverse.join('')
          queue_message(msg)
        }.join("\r\n")    # reverse string
      end
    end
  end

  def on_join( peer_id, peer_nick )
    queue_message( 'hello ' + peer_id )
  end

end


class KotosakaSessionHandlerFactory
  def create( msnm, session )
    KotosakaSessionHandler.new( msnm, session )
  end
end



if __FILE__ == $0


  USERID = '***@hotmail.com'          # account for an IM agent
  PASSWD = '***'                      # password


  # start logging

  logfile = $stdout
  Net::InstantMessaging::MSNMessenger::ProtocolHandler.logfile = logfile
  now = Time.now
  process_tag = now.strftime('%Y%m%d%H%M%S') + now.usec.to_s
  logfile << "process start #{process_tag}\n"


  # initialize service

  msnm = Net::InstantMessaging::MSNMessenger.new( USERID, PASSWD,
                                    KotosakaSessionHandlerFactory.new )
  msnm.ns.synchronize
  msnm.ns.privacy_mode :BLP_ALLOW

  # start service

  msnm.ns.online
  msnm.listen     # -> listening...
  msnm.logout

  # finish logging

  logfile << "process finish #{process_tag}\n"


end
