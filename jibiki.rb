#!/usr/local/bin/ruby -wKu

=begin

= jibiki.rb version 0.3.0  2001/11/26 - 2002/11/28

Copyright (c) 2001 2002  msnm@zerobase.jp

This program is free software. You can re-distribute and/or
modify this program under the same terms as Ruby itself,
Ruby Distribute License or GNU General Public License.

== What is This?

search quoted words

=end


require 'msnm'
require 'net/http'


class JibikiSessionHandler < Net::InstantMessaging::MSNMessenger::SessionHandler

  def handle_message( peer_id, peer_nick, msg_header, msg_body )

    if msg_header =~ /\r\nContent-Type: text\/plain/um

      search_fmt = '/search?hl=ja&lr=&q=%s'
      reply_lines = []

      msg_body.split("\r\n").each do |msg_line|

        search_words = []
        msg_line.scan(/\343\200\214(.+?)\343\200\215/n) do |search_word,|
          search_words << search_word
        end

        search_words.each do |search_word|

          search_path = format( search_fmt, urlencode(search_word) )
          search_url = 'http://www.google.com' + search_path
          hit_count = 0

          begin
            Net::HTTP::start('www.google.com') do |http|
              http.get(search_path) do |html|
                if m = /swrnum=(\d+)/.match(html)
                  hit_count = ( m[-1] || 0 ).to_i
                end
              end
            end
          rescue
            hit_count = 0
          end

          reply_lines << format( '%s  %s  ( %d hit)', search_word, search_url, hit_count )
        end

      end

      unless reply_lines.empty?
        queue_message(reply_lines.join("\r\n"))
      end

    end

  end


  def urlencode( str )
    str.split(//n).collect{|c|format('%%%02X',c[0])}.join('')
  end


  def on_join( peer_id, peer_nick )
    queue_message( 'hello ' + peer_id )
  end


end



class JibikiSessionHandlerFactory

  def create( msnm, session )
    JibikiSessionHandler.new( msnm, session )
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
                         JibikiSessionHandlerFactory.new )
  msnm.ns.synchronize
  msnm.ns.privacy_mode :BLP_ALLOW

  # start service

  msnm.ns.online
  msnm.listen     # -> listening...
  msnm.logout

  # finish logging

  logfile << "process finish #{process_tag}\n"


end
