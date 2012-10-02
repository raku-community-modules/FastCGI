use v6;

class FastCGI;

use FastCGI::Connection;

has Int $.port = 9119;
has Str $.addr = 'localhost';
has $.socket;

has $.PSGI = True;   ## Set to False to use raw HTTP responses.

## Settings for FastCGI management records.
## You can override these per-application, but support is limited.
has $.max-connections = 1;
has $.max-requests = 1;
has $.multiplex = False;

method connect (:$port=$.port, :$addr=$.addr)
{
  $.socket = IO::Socket::INET.new(
    :localhost($addr), 
    :localport($port), 
    :listen(1)
  );
}

method accept ()
{
  if (! $.socket)
  {
    self.connect();
  }
  my $connection = $.socket.accept() or return;
  FastCGI::Connection(:socket($connection), :parent(self));
}

method handle (&closure)
{
  $*ERR.say: "[{time}] FastCGI is ready and waiting.";
  while (my $connection = self.accept)
  {
    $connection.handle-requests(&closure);
    $connection.close;
  }
}

