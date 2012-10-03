use v6;

class FastCGI::Request;

use FastCGI::Constants;
use FastCGI::Protocol;

has $.connection;
has Buf $.input;
has Int $.id;
has Buf $!params;

method param (Buf $param)
{
  if $!params.defined
  {
    $!params ~= $param;
  }
  else
  {
    $!params = $param;
  }
}

method in (Buf $stdin)
{
  if $!input.defined
  {
    $!input ~= $stdin;
  }
  else
  {
    $!input = $stdin;
  }
}

method env
{
  ## First, parse the environment.
  my %env = parse_params($!params);

  ## Now add some meta data.
  %env<fastcgi.request> = self;
  if $.connection.parent.PSGI
  {
    %env<psgi.version>      = [1,0];
    %env<psgi.url_scheme>   = 'http'; ## FIXME: detect this.
    %env<psgi.multithread>  = False;
    %env<psgi.multiprocess> = False;
    %env<psgi.input>        = $.input;
    %env<psgi.errors>       = $.connection.err;
    %env<psgi.run_once>     = False;
    %env<psgi.nonblocking>  = False; ## Allow when NBIO.
    %env<psgi.streaming>    = False; ## Allow eventually?
  }
  return %env;
}

