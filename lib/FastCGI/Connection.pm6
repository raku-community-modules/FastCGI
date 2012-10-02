use v6;

class FastCGI::Connection;

use FastCGI::Request;
use FastCGI::Response;
use FastCGI::Errors;
use FastCGI::Constants;
use FastCGI::Protocol;
use FastCGI::Protocol::Constants;

has $.socket;
has $.parent;
has $.err = FastCGI::Errors.new;
has %!requests;

method requests (&closure)
{
  while my Buf $record = $.socket.recv()
  {
    my %record = parse_record($record);
    my $id = %record<request-id>;
    my $type = %record<type>;
    given $type
    {
      when FCGI_BEGIN_REQUEST
      {
        if %!requests.exists($id) { die "Request of id $id already exists"; }
        %!requests{$id} = FastCGI::Request.new(:$id, :connection(self));
      }
      when FCGI_PARAMS
      {
        if ! %!requests.exists($id) { die "Invalid request id: $id"; }
        my $req = %!requests{$id};
        if %record<content>
        {
          $req.param(%record<content>);
        }
      }
      when FCGI_STDIN
      {
        if ! %!requests.exists($id) { die "Invalud request id: $id"; }
        my $req = %!requests{$id};
        if %record<content>
        {
          $req.in(%record<content>);
        }
        else
        {
          my $return = &closure($req.env);
          self.send($id, $return);
          return;
        }
      }
    }
  }
}

method send ($request-id, $output)
{
  my $http_message;
  if $.parent.PSGI
  {
    my $code = $response-data[0];
    my $message = get_http_status_msg($code);
    my $headers = "Status: $code $message"~CRLF;
    for @($response-data[1]) -> $header
    {
      $headers ~= $header.key ~ ": " ~ $header.value ~ CRLF;
    }
    $http_message = ($headers~CRLF).encode;
    for @($response-data[2]) -> $body
    {
      if $body ~~ Buf
      {
        $http_message ~= $body;
      }
      else
      {
        $http_message ~= $body.Str.encode;
      }
    }
  }
  else
  {
    if $response-data ~~ Buf
    {
      $http_message = $response-data;
    }
    else
    {
      $http_message = $response-data.Str.encode;
    }
  }

  my $request;
  if $.err.messages.elems > 0
  {
    my $stderr = $.err.messages.join.encode;
    $request = build_end_request($request-id, $stdout, $stderr);
  }
  else
  {
    $request = build_end_request($request-id, $stdout);
  }

  $.socket.send($request);
}

