use v6;

class FastCGI::Connection;

use FastCGI::Request;
use FastCGI::Response;
use FastCGI::Errors;

has $.socket;
has $.parent;
has $.err = FastCGI::Errors.new;

method request ()
{
  FastCGI::Request(:connection(self)).parse;
}

method send ($output)
{
  FastCGI::Response(:connection(self)).send($output);
}

