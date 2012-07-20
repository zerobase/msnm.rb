# echo.rb

require 'msnm'

MSNMessenger = Net::InstantMessaging::MSNMessenger

class EchoSessionHandler < MSNMessenger::SessionHandler

  def handle_message( peer_id, peer_nick, msg_header, msg_body )
    if msg_header =~ /\r\nContent-Type: text\/plain/um
      queue_message(msg_body) # �󂯎�������b�Z�[�W�����̂܂ܕԂ�(echo����)
    end
  end

end

class EchoSessionHandlerFactory # Factory
  def create( msnm, session )
    EchoSessionHandler.new( msnm, session )
  end
end

USERID = '***@hotmail.com'  # ���̃G�[�W�F���g���g���A�J�E���g��
PASSWD = '***'             # ���̃p�X���[�h

msnm = MSNMessenger.new( USERID, PASSWD, EchoSessionHandlerFactory.new )
msnm.ns.synchronize           # MSN�T�[�o����R���^�N�g���X�g���擾
msnm.ns.online                # �X�e�[�^�X���u�I�����C���v��
msnm.listen                   # �ڑ���t��ԂɂȂ�
msnm.logout                   # ���O�A�E�g����
