# MSN Messenger protocol handler (Ruby)

msnm.rb version 0.3.0  2001/11/18 - 2005/01/28

Copyright (c) 2001,2002,2005 ZEROBASE, Inc.  http://zerobase.jp/

This program is free software. You can re-distribute and/or
modify this program under the same terms as Ruby itself,
Ruby Distribute License or GNU General Public License.


## What is This Module?

This module provides the framework for instant messaging(IM).


## How to Use This Module?

See template methods in `Net::InstantMessaging::MSNMessenger::SessionHandler`.
You do not need to implement a subclass of `SessionHandler`.
You need to implement template methods in your class and
register an object of its class as an event handler object.
