unit class FastCGI:ver<0.9.1>:auth<zef:raku-community-modules>;

use FastCGI::Connection;
use FastCGI::Logger;

has Int $.port = 9119;
has Str $.addr = 'localhost';
has $.socket;

has $.PSGI  = False; ## Include PSGI Classic headers.
has $.P6SGI = True;  ## Include default P6SGI headers.
                     ## If niehter are used use raw HTTP headers.

## Settings for FastCGI management records.
## You can override these per-application, but support is limited.
has $.max-connections = 1;
has $.max-requests = 1;
has $.multiplex = False;

## Settings for logging/debugging.
has $.log   = True;
has $.debug = False;
has $.fancy-log = True;

method connect(:$port = $.port, :$addr = $.addr) {
    $!socket = IO::Socket::INET.new(
      :localhost($addr), 
      :localport($port),
      :listen
    )
}

method accept() {
    self.connect unless $.socket;
    with $.socket.accept -> $connection {
        FastCGI::Connection.new(:socket($connection), :parent(self))
    }
    else {
        Nil
    }
}

method handle (&closure) {
    my $log;
    if $.log {
        if $.debug {
            $log = FastCGI::Logger.new(:name<FastCGI>, :string($.fancy-log));
        }
        else {
            $log = FastCGI::Logger.new(:string($.fancy-log), :!duration);
        }
    }
    $log.say: "Loaded and waiting for connections.";

    while self.accept -> $connection {
        $log.say: "Received request." if $.log;
        $connection.handle-requests(&closure);
        $log.say: "Completed request." if $.log;
        $connection.close;
    }
}

# vim: expandtab shiftwidth=4
