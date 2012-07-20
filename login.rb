#!/usr/local/bin/ruby -wKs

=begin

= login.rb version 0.1.0 2001/12/14 - 2002/11/28

Copyright (c) 2001 2002  msnm@zerobase.jp

This program is free software. You can re-distribute and/or
modify this program under the same terms as Ruby itself,
Ruby Distribute License or GNU General Public License.

== What is This?

login MSN Messenger Service. do nothing.

=end



require 'msnm'



class LoginSessionHandler < Net::InstantMessaging::MSNMessenger::SessionHandler

end


class LoginSessionHandlerFactory

  def create( msnm, session )
    LoginSessionHandler.new( msnm, session )
  end

end




if __FILE__ == $0


  USERID = ARGV[0]
  PASSWD = ARGV[1]

  unless USERID && PASSWD
    print "login.rb <user_id> <password>\n"
    exit
  end

  Net::InstantMessaging::MSNMessenger::ProtocolHandler.logfile = $stdout
  msnm = Net::InstantMessaging::MSNMessenger.new( USERID, PASSWD,
                                          LoginSessionHandlerFactory.new )
  msnm.ns.synchronize
  msnm.ns.online
  msnm.listen
  msnm.logout


end
