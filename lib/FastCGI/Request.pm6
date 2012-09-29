use v6;

class FastCGI::Request;

use FastCGI::Constants;

has $.connection;
has %.env;
has $.input;

method parse ()
{
  while my Buf $record = $.connection.socket.recv()
  {
    ## TODO: parse the record.
  }

  ## Now add some meta data.
  %.env<fastcgi.request> = self;
  if $.connection.parent.PSGI
  {
    %.env<psgi.version>      = [1,0];
    %.env<psgi.url_scheme>   = 'http'; ## FIXME: detect this.
    %.env<psgi.multithread>  = False;
    %.env<psgi.multiprocess> = False;
    %.env<psgi.input>        = $.input;
    %.env<psgi.errors>       = $.connection.err;
    %.env<psgi.run_once>     = False;
    %.env<psgi.nonblocking>  = False; ## Allow when NBIO.
    %.env<psgi.streaming>    = False; ## Allow eventually?
  }

  return self;
}

