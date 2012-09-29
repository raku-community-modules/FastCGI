use v6;

class FastCGI::Response;

use HTTP::Status;
use FastCGI::Constants;

has $.connection;

method send ($response-data)
{
  my $http_message;
  if $.connection.parent.PSGI
  {
    my $code = $response-data[0];
    my $message = get_http_status_msg($code);
    my $headers = "Status: $code $message"~CRLF;
    for @($response-data[1]) -> $header
    {
      $headers ~= $header.key ~ ": " ~ $header.value ~ CRLF;
    }
    my $body = $response-data[2].join(CRLF);
    $http_message = $headers~CRLF~$body;
  }
  else
  {
    $http_message = $response-data;
  }
  ## TODO: build and send the output records here.

  return self;
}

