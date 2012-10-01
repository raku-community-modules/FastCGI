use v6;

module FastCGI::Protocol;

use FastCGI::Constants;
use FastCGI::Protocol::Constants :ALL;

constant ERRMSG_OCTETS    = 'Insufficient number of octets to parse %s';
constant ERRMSG_MALFORMED = 'Malformed record %s';
constant ERRMSG_VERSION   = 'Protocol version mismatch (0x%.2X)';
constant ERRMSG_OCTETS_LE = 'Invalid argument: "%s" cannot exceed %u octets';

sub throw ($message, *@args)
{
  die sprintf($message, |@args);
}

sub build_header 
($type, $request-id, $content-length, $padding-length) is export
{
  return pack(
    FCGI_Header_P, FCGI_VERSION_1, $type, $request-id,
    $content-length, $padding-length
  );
}

sub parse_header (Buf $octets, Bool :$hash) is export
{
  $octets.bytes >= 8 || throw ERRMSG_OCTETS, 'FCGI_Header';
  $octets[0] == FCGI_VERSION_1 || throw ERRMSG_VERSION, $octets.unpack('C');
  my @vals = $octets.unpack(FCGI_Header_U);
  if $hash
  {
    my %h = 'type', 'request-id', 'content-length', 'padding-length' Z @vals;
    return %h;
  }
  return @vals;
}

sub build_begin_request_body ($role, $flags) is export
{
  return pack(FCGI_BeginRequestBody, $role, $flags);
}

sub parse_begin_request_body (Buf $octets) is export
{
  $octets.bytes >= 8 || throw ERRMSG_OCTETS, 'FCGI_BeginRequestBody';
  return $octets.unpack(FCGI_BeginRequestBody);
}

sub build_end_request_body ($app-status, $protocol-status) is export
{
  return pack(FCGI_EndRequestBody, $app-status, $protocol-status);
}

sub parse_end_request_body (Buf $octets) is export
{
  $octets.bytes >= 8 || throw ERRMSG_OCTETS, 'FCGI_EndRequestBody';
  return $octets.unpack(FCGI_EndRequestBody);
}

sub build_unknown_type_body ($type) is export
{
  return pack(FCGI_UnknownTypeBody, $type);
}

sub parse_unknown_type_body (Buf $octets) is export
{
  $octets.bytes >= 8 || throw ERRMSG_OCTETS, 'FCGI_UnknownTypeBody';
  return $octets.unpack(FCGI_UnknownTypeBody);
}

sub build_begin_request_record ($request-id, $role, $flags) is export
{
  return build_record(FCGI_BEGIN_REQUEST, $request-id, 
    build_begin_request_body($role, $flags));
}

sub build_end_request_record 
($request-id, $app-status, $protocol-status) is export
{
  return build_record(FCGI_END_REQUEST, $request-id,
    build_end_request_body($app-status, $protocol-status));
}

sub build_unknown_type_record ($type) is export
{
  return build_record(FCGI_UNKNOWN_TYPE, FCGI_NULL_REQUEST_ID,
    build_unknown_type_body($type));
}

sub build_record ($type, $request-id, Buf $content?) is export
{
  my $content-length = $content.defined ?? $content.bytes !! 0;
  my $padding-length = (8 - ($content-length % 8)) % 8;

  $content-length <= FCGI_MAX_CONTENT_LEN 
    || throw ERRMSG_OCTETS_LE, 'content', FCGI_MAX_CONTENT_LEN;

  my $res = build_header($type, $request-id, $content-length, $padding-length);

  if $content-length
  {
    $res ~= $content;
  }

  if $padding-length
  {
    $res ~= (ZERO x $padding-length).encode;
  }

  return $res;
}

sub parse_record (Buf $octets, Bool :$hash) is export
{
  my ($type, $request-id, $content-length) = parse_header($octets);
  $octets.bytes >= FCGI_HEADER_LEN + $content-length 
    || throw ERRMSG_OCTETS, 'FCGI_Record';

  my $content = $octets.subbuf(FCGI_HEADER_LEN, $content-length);

  if $hash
  {
    return parse_record_body($type, $request-id, $content);
  }
  return $type, $request-id, $content;
}

sub parse_record_body ($type, $request-id, $content) is export
{
  my $content-length = $content.bytes;
  $content-length <= FCGI_MAX_CONTENT_LEN
    || throw ERRMSG_OCTETS_LE, 'content', FCGI_MAX_CONTENT_LEN;
  
  my %record = { :$type, :$request-id };
  
  given $type
  {
    when FCGI_BEGIN_REQUEST
    {
      ($request-id != FCGI_NULL_REQUEST_ID && $content-length == 8)
        || throw ERRMSG_MALFORMED, FCGI_RecordNames[$type];
      %record<role flags> = parse_begin_request_body($content);
    }
    when FCGI_ABORT_REQUEST
    {
      ($request-id != FCGI_NULL_REQUEST_ID && $content-length == 0)
        || throw ERRMSG_MALFORMED, FCGI_RecordNames[$type];
    }
    when FCGI_END_REQUEST
    {
      ($request-id != FCGI_NULL_REQUEST_ID && $content-length == 8)
        || throw ERRMSG_MALFORMED, FCGI_RecordNames[$type];
      %record<app-status protocol-status> = parse_end_request_body($content);
    }
    when FCGI_PARAMS | FCGI_STDIN | FCGI_STDOUT | FCGI_STDERR | FCGI_DATA
    {
      ($request-id != FCGI_NULL_REQUEST_ID)
        || throw ERRMSG_MALFORMED, FCGI_RecordNames[$type];
      %record<content> = $content-length ?? $content !! Nil;
    }
    when FCGI_GET_VALUES | FCGI_GET_VALUES_RESULT
    {
      ($request-id == FCGI_NULL_REQUEST_ID)
        || throw ERRMSG_MALFORMED, FCGI_RecordNames[$type];
      %record<values> = parse_params($content);
    }
    when FCGI_UNKNOWN_TYPE
    {
      ($request-id == FCGI_NULL_REQUEST_ID && $content-length == 8)
        || throw ERRMSG_MALFORMED, FCGI_RecordNames[$type];
      %record<unknown-type> = parse_unknown_type_body($content);
    }
    default
    {
      %record<content> = $content if $content-length;
    }
  }
  return %record;
}

## TODO: finish me, please?

sub build_stream ($type, $request-id, $content, Bool :$terminate)
{
}

sub build_params (%params)
{
}

sub parse_params (Buf $octets)
{
}


