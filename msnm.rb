=begin


= msnm.rb version 0.3.0  2001/11/18 - 2005/01/28

Copyright (c) 2001,2002,2005 ZEROBASE, Inc.  http://zerobase.jp/

This program is free software. You can re-distribute and/or
modify this program under the same terms as Ruby itself,
Ruby Distribute License or GNU General Public License.


== What is This Module?

This module provides the framework for instant messaging(IM).


== How to Use This Module?

See template methods in Net::InstantMessaging::MSNMessenger::SessionHandler.
You do not need to implement a subclass of SessionHandler.
You need to implement template methods in your class and
register an object of its class as an event handler object.

=end



require 'socket'
require 'thread'
require 'md5'
require 'forwardable'
require 'net/https'


module Net


  module InstantMessaging


    class MSNMessenger


      CRLF = "\r\n"


      extend Forwardable


      def_delegators( '@ns', 'online' )
      def_delegators( '@ns', 'offline' )
      def_delegators( '@ns', 'user_nick' )
      def_delegators( '@ns', 'set_nick' )
      def_delegators( '@ns', 'synchronize' )
      def_delegators( '@ns', 'list' )
      def_delegators( '@ns', 'allow_mode' )
      def_delegators( '@ns', 'privacy_mode' )
      def_delegators( '@ns', 'add_user' )
      def_delegators( '@ns', 'remove_user' )


      # quit service
      def logout
        @session_handlers.each { |sh| sh.session_out }
        @ns.offline
        @ns.logout
      end


      # listening... (wait for service)
      def listen
        @main_thread = Thread.current
        Thread.stop
      end


      # stop listening
      def wakeup
        @main_thread.wakeup      # quit listening
      end


      # call user and start new session
      def call( *target_users )
        sess =  @ns.new_switchboard
        ans_users = sess.call( *target_users )
        sh = @session_handler_factory.create( self, sess )
        @session_handlers.push sh
        if ans_users.size > 0
          sh
        else
          sh.session_out
          nil
        end
      end


      # called from other
      # (event handler method)
      def on_ringing( sess, session_id, ss_cookie, calling_id, calling_nick )
        handler = @session_handler_factory.create( self, sess )
        @session_handlers.push handler
        Thread.start { sess.answer session_id, ss_cookie }
        handler
      end


      # added to other's contact list
      # (event handler method)
      def on_added( cl_type, cl_serial, cl_userid, cl_nick )
        if cl_type == :LST_REVERSE || cl_type == :LST_ALLOW
          Thread.start { @ns.add_user :LST_ALLOW, cl_userid, cl_nick }
          Thread.start { @ns.add_user :LST_FORWARD, cl_userid, cl_nick }
        end
      end


      def wall( msg, hdr = nil )
        @session_handlers.each { |sh| sh.queue_message( msg, hdr ) }
      end


      # a SessionHandler object unregister itself by calling this method
      # (callback method)
      def on_session_out( sess )
        @session_handlers.delete sess
      end


      def initialize( user_id, passwd, session_handler_factory )
        @user_id = user_id
        @session_handler_factory = session_handler_factory
        @ds = DispatchServer.new( user_id )
        notification_handler = self
        @ns = @ds.login( passwd, notification_handler )
        @session_handlers = []
        @main_thread = nil
      end


      attr_reader :ds, :ns



      class SessionHandler      # Strategy

        TIMEOUT = 5

        # <template methods>
        #
        # private
        #
        #   def handle_message( peer_id, peer_nick, msg_header, msg_body )
        #
        # public   (event handlers)
        #
        #   def on_ans
        #   def on_join( peer_id, peer_nick )
        #   def on_bye( peer_id )
        #   def on_out
        #
        #   (not implemented yet)
        #   def on_ack
        #   def on_nack
        #
        # </template methods>


        public


        def session_out
          @msg_recv_queue.push nil
          @recv_t.join
          @send_t.join
          @msnm.on_session_out( self )
          @sess.disconnect
        end


        def on_out
          session_out
        end


        def on_bye( peer_id )
          if @sess.session_users.size.zero?
            session_out
          end
        end


        def queue_message( msg_body, msg_header = nil )
          @msg_send_queue.push [ msg_body, msg_header ]
        end


        def on_message( peer_id, peer_nick, msg )
          @msg_recv_queue.push [ peer_id, peer_nick, msg ]
        end


        private


        def send_loop
          while senddata = @msg_send_queue.pop
            @tick = Time.now
            content, header = senddata
            @sess.send_message2( content, header )
          end
        end


        def recv_loop
          while recvdata = @msg_recv_queue.pop
            @tick = Time.now
            peer_id, peer_nick, msg = recvdata
            msg_header, msg_body = msg.split( /\r\n\r\n/um, 2 )
            handle_message( peer_id, peer_nick,
                                        msg_header, msg_body )
          end
          @msg_send_queue.push nil
        end


        def initialize( msnm, sess )
          @msnm = msnm
          @sess = sess
          @sess.set_event_handler self
          @msg_recv_queue = SizedQueue.new(1000)
          @msg_send_queue = SizedQueue.new(1000)
          @send_t = Thread.start { send_loop }
          @recv_t = Thread.start { recv_loop }
          @tick = Time.now
          @killer = Thread.start do
            while true
              sleep 1
              if Time.now - @tick > TIMEOUT
                session_out
                Thread.exit
              end
            end
          end
        end


      end  # class SessionHandler



      class User


        def to_str
          format '%s <%s>', @nick, user_id
        end


        alias :to_s :to_str


        def initialize( user_id, nick )
          @user_id = user_id
          @nick = nick
        end


        attr_accessor :user_id, :nick


      end  # class User



      class ProtocolHandler


        # constants


        XLN_STATUS = {
          :XLN_ONLINE   =>  'NLN',     # Online
          :XLN_OFFLINE  =>  'FLN',     # Offline
          :XLN_LOGIN    =>  'ILN',     # Login(online)
          :XLN_HIDDEN   =>  'HDN',     # Hidden/Inisible
          :XLN_BUSY     =>  'BSY',     # Busy
          :XLN_IDLE     =>  'IDL',     # Idle
          :XLN_BACK     =>  'BRD',     # Be Right Back
          :XLN_AWAY     =>  'AWY',     # Away From Computer
          :XLN_PHONE    =>  'PHN',     # On The Phone
          :XLN_LUNCH    =>  'LUN',     # Out To Lunch
        }


        LST_TYPE = {
          :LST_FORWARD  =>  'FL',   # Forward List
          :LST_REVERSE  =>  'RL',   # Reverse List
          :LST_ALLOW    =>  'AL',   # Allow List
          :LST_BLOCK    =>  'BL',   # Block List
        }


        ACK_MODE = {
          :ACK_UNACKNOWLEDGE   => 'U',
          :ACK_NEGATIVE        => 'N',
          :ACK_ACKNOWLEDGE     => 'A',
        }


        GTC_MODE = {
          :GTC_NOASK  => 'N',
          :GTC_ASK    => 'A',
        }


        BLP_MODE = {
          :BLP_ALLOW  => 'AL',
          :BLP_BLOCK  => 'BL',
        }


        def url_escape(str)     # from cgi-lib.rb
          return nil if str.nil?
          str.gsub(/[^a-zA-Z0-9_\-.]/n){ sprintf("%%%02X", $&.unpack("C")[0]) }
        end

        def url_unescape(str)   # from cgi-lib.rb
          return nil if str.nil?
          str.gsub(/\+/, ' ').gsub(/%([0-9a-fA-F]{2})/){ [$1.hex].pack("c") }
        end



        # transaction/session queue


        def pop_transaction_queue( trid )
          queue = @transaction_queues[trid]
          queue.pop if queue
        end


        def delete_transaction_queue( trid )
          queue = @transaction_queues[trid]
          if queue.nil?
            raise InvalidTransactionID,
                    format( 'invalid TransactionID - %d', trid )
          end
          @transaction_queues.delete( trid )
        end


        def pop_session_queue( peer_id )
          @session_queues[peer_id].pop
        end


        def delete_session_queue( peer_id )
          queue = @session_queues[peer_id]
          if queue.nil?
            raise InvalidSessionID,
                    format( 'invalid PeerID - %s', peer_id )
          end
          @session_queues.delete( peer_id )
        end



        def wait_transaction( trid )
          ret = pop_transaction_queue( trid )
          delete_transaction_queue( trid )
          ret
        end


        def wait_session( peer_id )
          ret = pop_session_queue( peer_id )
          delete_session_queue( peer_id )
          ret
        end


        # protocol command


        def ver
          send_command( 'VER %d %s'+CRLF, PROTOCOL_VER.join(' ') )
        end
        
        
        def cvr
          locale = '0x0411'
          ostype = 'win'
          osver = '6.00'
          osarch = 'i386'
          cliname = 'MSNMSGR'
          cliver = '6.2.0137'
          send_command( 'CVR %s %s %s %s %s %s %s MSMSGS %s'+CRLF,
                       locale, ostype, osver, osarch, cliname, cliver, @user_id )
        end


        def inf
          send_command( 'INF %d'+CRLF )
        end


        def usr_i
          send_command( 'USR %d TWN I %s'+CRLF, @user_id )
        end


        def usr_s( ticket )
          send_command( 'USR %d TWN S %s'+CRLF, ticket )
        end


        def rea( user_id, nickname )
          return if nickname.nil? | nickname.empty?
          nn = url_escape( nickname )
          send_command( 'REA %d %s %s'+CRLF, user_id, nn )
        end


        def syn( serial )
          send_command( 'SYN %d %d'+CRLF, serial )
        end


        def gtc( mode )
          send_command( 'GTC %d %s'+CRLF, GTC_MODE[mode] )
        end


        def blp( mode )
          send_command( 'BLP %d %s'+CRLF, BLP_MODE[mode] )
        end


        def lst( list_type )
          send_command( 'LST %d %s'+CRLF, LST_TYPE[list_type] )
        end


        def add( list_type, peer_id, peer_nick )
          send_command( 'ADD %d %s %s %s'+CRLF, LST_TYPE[list_type],
                                  peer_id, url_escape( peer_nick ) )
        end


        def rem( list_type, peer_id )
          send_command( 'REM %d %s %s'+CRLF, LST_TYPE[list_type], peer_id )
        end


        def chg( status )
          send_command( 'CHG %d %s'+CRLF, XLN_STATUS[status] )
        end


        def xfr_sb
          send_command( 'XFR %d SB'+CRLF )
        end


        def usr_sb( cookie )
          send_command( 'USR %d %s %s'+CRLF, @user_id, cookie )
        end


        def cal( peer_id )
          send_command( 'CAL %d %s'+CRLF, peer_id )
        end


        def ans( session_id, ss_cookie )
          send_command( 'ANS %d %s %s %d'+CRLF, @user_id, ss_cookie, session_id )
        end


        def msg( content, header = nil, ack_mode = :ACK_UNACKNOWLEDGE )
          mesg = 'MIME-Version: 1.0' + CRLF
          if header
            mesg += header.to_s + CRLF
          else
            mesg += 'Content-Type: text/plain; charset=UTF-8' + CRLF
          end
          if content
            mesg += CRLF + content
          end
          send_command( 'MSG %d %s %d'+CRLF+'%s',
                          ACK_MODE[ack_mode], mesg.size, mesg )
        end


        def out
          sock_write 'OUT'+CRLF
        end


        # control


        def disconnect
          out
          if Thread.current == @sock_parser_thread
            terminate
          else
            @sock_parser_thread.join
          end
        end


        def terminate
          if self.instance_variables.include?( '@notification_server' )
            @notification_server.delete_switchboard( self )
          end
          @sock.close unless @sock.closed?
        end


        def self.logfile=( logfile )
          @@logfile = logfile
        end


        def set_event_handler( obj )
          @eh_m.synchronize { @event_handler = obj }
        end


        attr_reader :user_id
        attr_reader :user_nick


        private


        @@logfile = nil


        PROTOCOL_VER = [ 'MSNP9', 'CVR0' ]
        MSN_MESSENGER_SERVER = 'messenger.hotmail.com'
        MSN_MESSENGER_PORT = '1863'


        def initialize( user_id, host, port = MSN_MESSENGER_PORT )

          @user_id = user_id
          @user_nick = nil

          @host = host
          @port = port
          @sock = TCPSocket.open( @host, @port )

          @transaction_id = 0
              # Transaction ID : initial value = 1 (incremented)

          @default_transaction_queue = SizedQueue.new(1000)
          @transaction_queues = Hash.new(@default_transaction_queue)
              # @transaction_queues[@transaction_id] = SizedQueue.new(1000)

          @default_session_queue = SizedQueue.new(1000)
          @session_queues = Hash.new(@default_session_queue)

          @event_handler = nil
          @eh_m = Mutex.new

          @sock_parser_thread = Thread.start { parse_sock_input }

        end


        def new_transaction_queue( new_trid = nil )
          new_trid ||= (@transaction_id += 1)
          @transaction_queues[new_trid] = SizedQueue.new(1000)
          new_trid
        end


        def push_transaction_queue( trid, val )
          queue = @transaction_queues[trid]
          queue.push val if queue
        end


        def push_session_queue( peer_id, val )
          @session_queues[peer_id].push val
        end


        def send_command(format_string, *params)
          trid = new_transaction_queue
          sock_write sprintf( format_string, trid, *params )
          trid
        end


        # regular expression for parsing


        RE_VER = /^VER (\d+) (.+)#{CRLF}/u
        RE_INF = /^INF (\d+) (.+)#{CRLF}/u
        RE_CVR = /^CVR (\d+) (.+)#{CRLF}/u
        RE_XFR_NS = /^XFR (\d+) NS ([^:]+)(?::(\d+))? 0 (.+)#{CRLF}/u
        RE_USR_NS_S = /^USR (\d+) (.+) S (.+)#{CRLF}/u
        RE_USR_NS_OK = /^USR (\d+) OK (.+) (.+)#{CRLF}/u
        RE_CHG = /^CHG (\d+) (.+)#{CRLF}/u
        RE_XFR_SB = /^XFR (\d+) SB ([^:]+)(?::(\d+))? CKI (.+)#{CRLF}/u
        RE_USR_SB = /^USR (\d+) OK (.+) (.+)#{CRLF}/u
        RE_CAL = /^CAL (\d+) (.+) (\d+)#{CRLF}/u
        RE_RNG = /^RNG (\d+) ([^:]+)(?::(\d+))? CKI (.+) (.+) (.+)#{CRLF}/u
        RE_IRO = /^IRO (\d+) (\d+) (\d+) (.+) (.+)#{CRLF}/u
        RE_ANS = /^ANS (\d+) OK#{CRLF}/u
        RE_JOI = /^JOI (.+) (.+)#{CRLF}/u
        RE_BYE = /^BYE (.+)#{CRLF}/u
        RE_OUT = /^OUT(?: (.+))?#{CRLF}/u
        RE_CHL = /^CHL 0 (.+)#{CRLF}/
        RE_MSG = /^MSG (.+) (.+) (\d+)#{CRLF}/u
        RE_ACK = /^(ACK|NAK) (\d+)#{CRLF}/u
        RE_REA = /^REA (\d+) (\d+) (.+) (.+)#{CRLF}/u
        RE_SYN = /^SYN (\d+) (\d+)#{CRLF}/u
        RE_GTC = /^GTC (\d+) (\d+) (A|N)#{CRLF}/u
        RE_BLP = /^BLP (\d+) (\d+) (AL|BL)#{CRLF}/u
        RE_XLN = /^(.LN) (\d+) ([A-Z]{3})(?: (.+) (.+))?.*#{CRLF}/u
        RE_LST = /^LST (\d+) (.+) (\d+) (\d+) (\d+)(?: ([^\s]+) (.+))?#{CRLF}/u
        RE_ADD = /^ADD (\d+) (.+) (\d+) (.+) (.+)#{CRLF}/u
        RE_REM = /^REM (\d+) (.+) (\d+) (.+)#{CRLF}/u
        RE_ERR = /^(\d{3})(?:\s+(\d+)?(?:\s+(.+)?)?)?#{CRLF}/u


        def parse_sock_input  # DO NOT CALL DIRECTLY (called from #initialize)

          while res = sock_gets

            case res

            when RE_VER

              trid = $1.to_i
              dialects = $2
              push_transaction_queue trid, dialects

            when RE_INF

              trid = $1.to_i
              security_package = $2
              push_transaction_queue trid, security_package

            when RE_CVR

              trid = $1.to_i
              ignore = $2
              push_transaction_queue trid, ignore

            when RE_XFR_NS

              trid = $1.to_i
              ns_host = $2
              ns_port = $3
              push_transaction_queue trid, [ ns_host, ns_port ]

            when RE_USR_NS_S

              trid = $1.to_i
              security_package = $2
              challenge_str = $3
              push_transaction_queue trid, [ security_package, challenge_str ]

            when RE_USR_NS_OK

              trid = $1.to_i
              user_id = $2
              @user_nick = url_unescape( $3 )
              push_transaction_queue trid, [ user_id, @user_nick ]

            when RE_CHG

              trid = $1.to_i
              status = $2
              push_transaction_queue trid, status

            when RE_XFR_SB

              trid = $1.to_i
              ss_host = $2
              ss_port = $3
              ss_cookie = $4
              push_transaction_queue trid, [ ss_host, ss_port, ss_cookie ]

            when RE_CAL

              trid = $1.to_i
              status = $2
              session_id = $3.to_i
              push_transaction_queue trid, [ status, session_id ]

            when RE_RNG

              session_id = $1.to_i
              ss_host = $2
              ss_port = $3
              ss_cookie = $4
              calling_id = $5
              calling_nick = url_unescape( $6 )

              ss = add_switchboard( ss_host, ss_port, ss_cookie )
              if @event_handler.respond_to? :on_ringing
                @event_handler.on_ringing( ss, session_id, ss_cookie,
                                               calling_id, calling_nick )
              end

            when RE_IRO

              trid = $1.to_i
              cl_entrynum = $2.to_i
              cl_size = $3.to_i
              cl_userid = $4
              cl_nick = url_unescape( $5 )
              push_transaction_queue trid, [ cl_entrynum, cl_size,
                                             cl_userid, cl_nick ]

            when RE_ANS

              trid = $1.to_i
              push_transaction_queue trid, nil

              if @event_handler.respond_to? :on_ans
                @event_handler.on_ans
              end

            when RE_JOI

              peer_id = $1
              peer_nick = url_unescape( $2 )
              push_session_queue peer_id, [ :SS_JOI, peer_id, peer_nick ]

              user_join peer_id, peer_nick

              if @event_handler.respond_to? :on_join
                @event_handler.on_join peer_id, peer_nick
              end

            when RE_BYE

              peer_id = $1
              push_session_queue peer_id, [ :SS_BYE ]

              user_bye peer_id

              if @event_handler.respond_to? :on_bye
                @event_handler.on_bye peer_id
              end

            when RE_OUT

              status = $1
              push_transaction_queue nil, status

              if @event_handler.respond_to? :on_out
                @event_handler.on_out
              end

              terminate

            when RE_CHL

              ch_str = $1
              ch_res = MD5.new( ch_str + 'Q1P7W2E4J9R8U3S5' ).hexdigest  # challenge response
              send_command( 'QRY %d msmsgs@msnmsgr.com 32'+CRLF+'%s', ch_res )

            when RE_MSG

              peer_id = $1
              peer_nick = url_unescape( $2 )
              msg_len = $3.to_i
              msg = sock_read msg_len
              push_session_queue peer_id, [ :SS_MSG, peer_id, peer_nick, msg ]

              if @event_handler.respond_to? :on_message
                @event_handler.on_message peer_id, peer_nick, msg
              end

            when RE_ACK

              status = $1
              trid = $2.to_i
              push_transaction_queue trid, status

            when RE_REA

              trid   = $1.to_i
              serial = $2.to_i
              userid = $3
              nick   = url_unescape( $4 )
              push_transaction_queue trid, [ userid, nick ]

            when RE_SYN

              trid = $1.to_i
              serial = $2.to_i
              push_transaction_queue trid, serial

            when RE_GTC

              trid = $1.to_i
              serial = $2.to_i
              status = GTC_MODE.index($3)
              push_transaction_queue trid, [ serial, status ]

            when RE_BLP

              trid = $1.to_i
              serial = $2.to_i
              status = BLP_MODE.index($3)
              push_transaction_queue trid, [ serial, status ]

            when RE_XLN

              ntfn_type = $1
              trid = $2.to_i
              ntfn_stat = $3
              peer_id = $4
              peer_nick = url_unescape( $5 )
              push_transaction_queue( trid,
                  [ ntfn_type, ntfn_stat, peer_id, peer_nick ] )

              if @event_handler.respond_to? :on_status
                @event_handler.on_status ntfn_stat, peer_id, peer_nick
              end

            when RE_LST

              trid = $1.to_i
              cl_type = LST_TYPE.index($2)
              cl_serial = $3.to_i
              cl_entrynum = $4.to_i
              cl_size = $5.to_i
              cl_userid = $6
              cl_nick = url_unescape( $7 )
              if cl_userid.nil?
                push_transaction_queue trid, nil
              else
                push_transaction_queue( trid,
                           [ cl_type, cl_serial,
                             cl_entrynum, cl_size,
                             cl_userid, cl_nick ] )
              end

            when RE_ADD

              trid = $1.to_i
              cl_type = LST_TYPE.index($2)
              cl_serial = $3.to_i
              cl_userid = $4
              cl_nick = url_unescape( $5 )
              push_transaction_queue( trid, [ cl_type, cl_serial,
                                              cl_userid, cl_nick ] )

              if @event_handler.respond_to? :on_added
                @event_handler.on_added( cl_type, cl_serial, cl_userid, cl_nick )
              end

            when RE_REM

              trid = $1.to_i
              cl_type = LST_TYPE.index($2)
              cl_serial = $3.to_i
              cl_userid = $4
              push_transaction_queue( trid, [ cl_type, cl_serial, cl_userid ] )

              if @event_handler.respond_to? :on_removed
                @event_handler.on_removed( cl_type, cl_serial, cl_userid )
              end

            when RE_ERR
              err_code = $1.to_i
              trid = $2.to_i
              err_desc = $3

              err = MSNPError.new( err_code, err_desc )
              push_transaction_queue( trid, err )

            else

              push_transaction_queue nil, res

            end

          end

          # sock_gets == nil => EOF

          terminate

        end


        # socket read/write


        def sock_write( str )
          begin
            if $DEBUG
              STDOUT.puts ">>> " + Time.now.strftime('%Y/%m/%d:%H:%M:%S ') +
                self.class.name.split('::')[-1] +
                format( "#<%s>\n%s\n", self.object_id, ( str || "(nil)" ) )
              STDOUT.flush
            end
            @sock.write str
          rescue
          end
        end


        def sock_gets
          str = nil
          begin
            str = @sock.gets
            if $DEBUG
              STDOUT.puts "<<< " + Time.now.strftime('%Y/%m/%d:%H:%M:%S ') +
                self.class.name.split('::')[-1] +
                format( "#<%s>\n%s\n", self.object_id, ( str || "(nil)" ) )
              STDOUT.flush
            end
          rescue
          end
          str
        end


        def sock_read( len )
          str = nil
          begin
            str = @sock.read( len )
            if $DEBUG
              STDOUT.puts "<<< " + Time.now.strftime('%Y/%m/%d:%H:%M:%S ') +
                self.class.name.split('::')[-1] +
                format( "#<%s>\n%s\n", self.object_id, ( str || "(nil)" ) )
              STDOUT.flush
            end
          rescue
          end
          str
        end


        class InvalidTransactionID < StandardError
        end

        class InvalidSessionID < StandardError
        end

        class MSNPError
          def initialize( code, desc )
            @code = code
            @desc = desc
          end
          attr_reader :code, :desc
          def to_s
            "code: <#{code}> desc: <#{desc}>"
          end
          def to_str
            to_s
          end
        end

      end  # class ProtocolHandler



      class NotificationServer < ProtocolHandler


        def login( passwd )
          wait_transaction( ver )
          wait_transaction( cvr )
          sec_pkg, ch_str = wait_transaction( usr_i )
          # HTTP: Passport Nexus
          https = Net::HTTP.new('nexus.passport.com',443)
          https.use_ssl = true
          resp = https.get('/rdr/pprdr.asp')
          m = resp['passporturls'].match('DALogin=(.*?),')
          loginurl = 'https://'+m[1]
          uri = URI.split(loginurl)
          # HTTP: Login Server
          https = Net::HTTP.new(uri[2],443)
          https.use_ssl = true
          auth_str = 'Passport1.4 OrgVerb=GET,OrgURL=http%3A%2F%2Fmessenger%2Emsn%2Ecom,sign-in='+url_escape(@user_id)+',pwd='+passwd+','+ch_str
          resp = https.get(uri[5], {'Authorization'=>auth_str, 'Host'=>uri[2]})
          if resp['location']
            uri = URI.split(resp['location'])
            https = Net::HTTP.new(uri[2],443)
            https.use_ssl = true
            resp = https.get(uri[5]+'?'+uri[7], {'Authorization'=>auth_str,'Host'=>uri[2]})
          end
          m = resp['authentication-info'].match(/'(t=.*?)'/)
          ticket = m[1]
          # MSNP: login
          wait_transaction( usr_s(ticket) )
        end


        def logout
          @switchboard_sessions.each do |ss|
            ss.disconnect
          end
          disconnect
        end


        def online
          delete_transaction_queue( chg( :XLN_ONLINE ) )
        end


        def offline
          delete_transaction_queue( chg( :XLN_OFFLINE ) )
        end


        def list( list_type = :LST_FORWARD )

          contactlist = {}
          trid = lst( list_type )

          while cl_item = pop_transaction_queue( trid )

            cl_type, cl_serial, cl_entrynum,
              cl_size, cl_userid, cl_nick = cl_item

            contactlist[cl_userid] = cl_nick

            break if cl_size == cl_entrynum

          end

          delete_transaction_queue( trid )
          contactlist

        end


        def add_user( list_type, peer_id, peer_nick )
          wait_transaction( add( list_type, peer_id, peer_nick ) )
        end


        def remove_user( list_type, peer_id )
          wait_transaction( rem( list_type, peer_id ) )
        end


        def set_nick( userid, nickname )
          wait_transaction( rea( userid, nickname ) )
        end


        def synchronize( serial = 0 )
          syn(serial)
        end


        def allow_mode( mode )
          wait_transaction( gtc( mode ) )
        end


        def privacy_mode( mode )
          wait_transaction( blp( mode ) )
        end


        def new_switchboard
          ss_host, ss_port, ss_cookie = wait_transaction( xfr_sb )
          ss = add_switchboard( ss_host, ss_port, ss_cookie )
          ss.auth( ss_cookie )
          ss
        end


        def delete_switchboard( ss )
          @ss_m.synchronize { @switchboard_sessions.delete ss }
        end


        private


        def add_switchboard( ss_host, ss_port, ss_cookie )
          ss = SwitchboardServer.new( @user_id, ss_host, ss_port, self )
          ss.set_event_handler @event_handler
          @ss_m.synchronize { @switchboard_sessions.push ss }
          ss
        end


        def initialize( user_id, host, port )
          super
          @switchboard_sessions = []
            # @switchboard_sessions.push switchboard
          @ss_m = Mutex.new
        end


      end  # class NotificationServer



      class DispatchServer < NotificationServer


        def login( passwd, event_handler )
          wait_transaction( ver )
          wait_transaction( cvr )
          ret = wait_transaction( usr_i )
          ns_host, ns_port = ret
          disconnect
          ns = NotificationServer.new( @user_id, ns_host, ns_port )
          ns.set_event_handler( event_handler )
          ns.login( passwd )
          return ns
        end


        private


        DS_HOST = MSN_MESSENGER_SERVER   # DispatchServer address
        DS_PORT = MSN_MESSENGER_PORT  # DispatchServer port


        def initialize( user_id, host = DS_HOST, port = DS_PORT )
          super
        end


      end  # class DispatchServer



      class SwitchboardServer < ProtocolHandler


        def auth( cookie )
          user_id, nick = wait_transaction( usr_sb(cookie) )
        end


        def answer( session_id, ss_cookie )

          @su_m.synchronize {

            @session_users = {}
            trid = ans( session_id, ss_cookie )

            while cl_item = pop_transaction_queue( trid )
              cl_entrynum, cl_size, cl_userid, cl_nick = cl_item
              @session_users[cl_userid] = cl_nick
            end

            delete_transaction_queue( trid )
            @session_users

          }

          disconnect if session_users.size == 0

        end


        def call( peers )

          cal_trids = {}
          ans_users = []

          peers.each do |peer_id|
            trid = cal( peer_id )
            cal_trids[ trid ] = peer_id
          end

          cal_trids.each do |trid,peer_id|
            ret = wait_transaction( trid )
            ans_users.push( peer_id ) unless ret.kind_of?( MSNPError )
          end

          return ans_users

        end


        def send_message( content, header = nil )
          delete_transaction_queue( msg( content, header ) )
        end


        def send_message2( content, header = nil )
          wait_transaction( msg( content, header, :ACK_ACKNOWLEDGE ) )
        end


        def session_users
          @su_m.synchronize { @session_users.clone }
        end


        private


        def user_join( peer_id, peer_nick )
          @su_m.synchronize { @session_users[peer_id] = peer_nick }
        end


        def user_bye( peer_id )
          @su_m.synchronize { @session_users.delete(peer_id) }
          disconnect if session_users.size == 0
        end


        def initialize( user_id, host, port, notification_server )
          super( user_id, host, port )
          @notification_server = notification_server
          @session_users = {}
            # @session_users.push[user_id] = user_nick
          @su_m = Mutex.new
        end


      end  # class SwitchboardServer


    end  # class MSNMessenger



  end  # module InstantMessaging


end  # module Net
