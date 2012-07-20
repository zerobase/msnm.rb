# echo.rb

require 'msnm'

MSNMessenger = Net::InstantMessaging::MSNMessenger

class EchoSessionHandler < MSNMessenger::SessionHandler

  def handle_message( peer_id, peer_nick, msg_header, msg_body )
    if msg_header =~ /\r\nContent-Type: text\/plain/um
      queue_message(msg_body) # 受け取ったメッセージをそのまま返す(echo動作)
    end
  end

end

class EchoSessionHandlerFactory # Factory
  def create( msnm, session )
    EchoSessionHandler.new( msnm, session )
  end
end

USERID = '***@hotmail.com'  # このエージェントが使うアカウント名
PASSWD = '***'             # そのパスワード

msnm = MSNMessenger.new( USERID, PASSWD, EchoSessionHandlerFactory.new )
msnm.ns.synchronize           # MSNサーバからコンタクトリストを取得
msnm.ns.online                # ステータスを「オンライン」に
msnm.listen                   # 接続受付状態になる
msnm.logout                   # ログアウトする
