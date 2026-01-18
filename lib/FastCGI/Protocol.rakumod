unit module FastCGI::Protocol;

use P5pack:ver<0.0.15+>:auth<zef:lizmat>;
use FastCGI::Constants;
use FastCGI::Protocol::Constants :ALL;
#use FastCGI::Logger;

constant ERRMSG_OCTETS    = 'Insufficient number of octets to parse %s';
constant ERRMSG_MALFORMED = 'Malformed record %s';
constant ERRMSG_VERSION   = 'Protocol version mismatch (0x%.2X)';
constant ERRMSG_OCTETS_LE = 'Invalid argument: "%s" cannot exceed %u octets';

sub throw($message, *@args) {
    die sprintf($message, |@args);
}

sub build_header(
  Int $type, Int $request-id, Int $content-length, Int $padding-length
) is export {
    pack FCGI_Header_P, FCGI_VERSION_1,
      $type, $request-id, $content-length, $padding-length
}

sub parse_header(
  Buf $octets, Bool :$hash
) is export {
    $octets.bytes >= 8 || throw ERRMSG_OCTETS, 'FCGI_Header';
    $octets[0] == FCGI_VERSION_1 || throw ERRMSG_VERSION, $octets.unpack('C');
    my @vals = $octets.unpack(FCGI_Header_U);
    $hash
      ?? %('type', 'request-id', 'content-length', 'padding-length' Z @vals)
      !! @vals
}

sub build_begin_request_body(
  Int $role, Int $flags
) is export {
    pack(FCGI_BeginRequestBody, $role, $flags)
}

sub parse_begin_request_body(Buf $octets) is export {
    $octets.bytes >= 8 || throw ERRMSG_OCTETS, 'FCGI_BeginRequestBody';
    $octets.unpack(FCGI_BeginRequestBody)
}

sub build_end_request_body(
  Int $app-status, Int $protocol-status
) is export {
    pack(FCGI_EndRequestBody, $app-status, $protocol-status)
}

sub parse_end_request_body(Buf $octets) is export {
    $octets.bytes >= 8 || throw ERRMSG_OCTETS, 'FCGI_EndRequestBody';
    $octets.unpack(FCGI_EndRequestBody)
}

sub build_unknown_type_body(Int $type) is export {
    pack(FCGI_UnknownTypeBody, $type)
}

sub parse_unknown_type_body(Buf $octets) is export {
    $octets.bytes >= 8 || throw ERRMSG_OCTETS, 'FCGI_UnknownTypeBody';
    $octets.unpack(FCGI_UnknownTypeBody)
}

sub build_begin_request_record(
  Int $request-id, Int $role, Int $flags
) is export {
    build_record(FCGI_BEGIN_REQUEST,
      $request-id, build_begin_request_body($role, $flags)
    )
}

sub build_end_request_record(
  Int $request-id, Int $app-status, Int $protocol-status
) is export {
    build_record(FCGI_END_REQUEST, $request-id,
      build_end_request_body($app-status, $protocol-status)
    )
}

sub build_unknown_type_record(Int $type) is export {
    build_record(FCGI_UNKNOWN_TYPE, FCGI_NULL_REQUEST_ID,
      build_unknown_type_body($type)
    )
}

multi sub build_record(
  Int $type, Int $request-id, Buf $content?
) is export {
    my $content-length = $content.defined ?? $content.bytes !! 0;
    my $padding-length = (8 - ($content-length % 8)) % 8;

    $content-length <= FCGI_MAX_CONTENT_LEN 
      || throw ERRMSG_OCTETS_LE, 'content', FCGI_MAX_CONTENT_LEN;

    my $res = build_header($type, $request-id, $content-length, $padding-length);

    $res ~= $content if $content-length;
    $res ~= (ZERO x $padding-length).encode if $padding-length;

    $res
}

multi sub build_record(
  Int $type, Int $request-id, Str $content
) is export {
    build_record($type, $request-id, $content.encode)
}

sub parse_record(Buf $octets, Bool :$raw) is export {
    my ($type, $request-id, $content-length) = parse_header($octets);
    $octets.bytes >= FCGI_HEADER_LEN + $content-length 
      || throw ERRMSG_OCTETS, 'FCGI_Record';

    my $content = $octets.subbuf(FCGI_HEADER_LEN, $content-length);

    $raw
      ?? ($type, $request-id, $content)
      !! parse_record_body($type, $request-id, $content)
}

sub parse_record_body(
  Int $type, Int $request-id, Buf $content
) is export {
    my $content-length = $content.bytes;
    $content-length <= FCGI_MAX_CONTENT_LEN
      || throw ERRMSG_OCTETS_LE, 'content', FCGI_MAX_CONTENT_LEN;
  
    my %record = :$type, :$request-id;
  
    given $type {
        when FCGI_BEGIN_REQUEST {
            ($request-id != FCGI_NULL_REQUEST_ID && $content-length == 8)
              || throw ERRMSG_MALFORMED, FCGI_RecordNames[$type];
            %record<role flags> = parse_begin_request_body($content);
        }
        when FCGI_ABORT_REQUEST {
            ($request-id != FCGI_NULL_REQUEST_ID && $content-length == 0)
              || throw ERRMSG_MALFORMED, FCGI_RecordNames[$type];
        }
        when FCGI_END_REQUEST {
            ($request-id != FCGI_NULL_REQUEST_ID && $content-length == 8)
              || throw ERRMSG_MALFORMED, FCGI_RecordNames[$type];
            %record<app-status protocol-status> = parse_end_request_body($content);
        }
        when FCGI_PARAMS | FCGI_STDIN | FCGI_STDOUT | FCGI_STDERR | FCGI_DATA {
            ($request-id != FCGI_NULL_REQUEST_ID)
              || throw ERRMSG_MALFORMED, FCGI_RecordNames[$type];
            %record<content> = $content-length ?? $content !! Nil;
        }
        when FCGI_GET_VALUES | FCGI_GET_VALUES_RESULT {
            ($request-id == FCGI_NULL_REQUEST_ID)
              || throw ERRMSG_MALFORMED, FCGI_RecordNames[$type];
            %record<values> = parse_params($content);
        }
        when FCGI_UNKNOWN_TYPE {
            ($request-id == FCGI_NULL_REQUEST_ID && $content-length == 8)
              || throw ERRMSG_MALFORMED, FCGI_RecordNames[$type];
            %record<unknown-type> = parse_unknown_type_body($content);
        }
        default {
            %record<content> = $content if $content-length;
        }
    }
    %record
}

multi sub build_stream(
  Int $type, Int $request-id, Buf $content, Bool :$end
) is export {
    my $len = $content.bytes;
    my $res = Buf.new;

    if $len {
        if $len < FCGI_SEGMENT_LEN {
            $res = build_record($type, $request-id, $content);
        }
        else {
            my $header = build_header($type, $request-id, FCGI_SEGMENT_LEN, 0);
            my $off = 0;
            while $len >= FCGI_SEGMENT_LEN {
                $res ~= $header;
                $res ~= $content.subbuf($off, FCGI_SEGMENT_LEN);
                $len -= FCGI_SEGMENT_LEN;
                $off += FCGI_SEGMENT_LEN;
            }
            $res ~= build_record(
              $type, $request-id, $content.subbuf($off, $len)
            ) if $len;
        }
    }

    $res ~= build_header($type, $request-id, 0, 0) if $end;

    $res
}

multi sub build_stream(
  Int $type, Int $request-id, Str $content, Bool :$end
) is export {
    build_stream($type, $request-id, $content.encode, :$end)
}

sub build_params (%params) is export {
    my $res = Buf.new;
    for %params.kv -> $k, $v {
        my $key = $k.encode;
        my $val = $v.defined ?? $v.Str.encode !! Nil;
        for $key, $val -> $rec {
            my $len = $rec.defined ?? $rec.bytes !! 0;
            $res ~= $len < 0x80 ?? pack('C', $len) !! pack('N', $len +| 0x8000_0000);
        }
        $res ~= $key;
        $res ~= $val if $val.defined;
    }
    $res
}

sub parse_params (Buf $octets) is export {
#    my $log = FastCGI::Logger.new(:name<P::pp>);
    my %params;
    $octets.defined || return %params;
    my $klen = 0;
    my $vlen = 0;
    my $olen = $octets.bytes;
    my $offset = 0;
#    $log.say: "Okay, let's process the params.";
    while $olen {
        for $klen, $vlen -> $len is rw {
#            $log.say: "Determining length size.";
            (1 <= $olen)
              || throw ERRMSG_OCTETS, 'FCGI_NameValuePair';
            $len = $octets.subbuf($offset++, 1).unpack('C');
            $olen--;
#            $log.say: "1 byte length: $len";
            next if $len < 0x80;

#            $log.say: "Length uses 4 bytes";
            (3 <= $olen)
              || throw ERRMSG_OCTETS, 'FCGI_NameValuePair';
            $len = (pack('C', $len +& 0x7F) ~ $octets.subbuf($offset, 3)).unpack('N');
            $offset += 3;
            $olen   -= 3;
#            $log.say: "4 byte length: $len";
        }
#        $log.say: "Ensuring content is correct.";
        ($klen + $vlen <= $olen)
          || throw ERRMSG_OCTETS, 'FCGI_NameValuePair';
#        $log.say: "Getting key";
        my $key = $octets.subbuf($offset, $klen).decode;
        $offset += $klen;
        $olen -= $klen;
#        $log.say: "Getting value";
        my $val = $octets.subbuf($offset, $vlen).decode;
        $offset += $vlen;
        $olen -= $vlen;
#        $log.say: "Setting param";
        %params{$key} = $val;
    }
#    $log.say: "Done processing parameters, returning.";
    %params
}

sub check_params (Buf $octets) is export {
    return False without $octets;

    my $klen = 0;
    my $vlen = 0;
    my $olen = $octets.bytes;
    my $offset = 0;
    while $offset < $olen {
        for $klen, $vlen -> $len is rw {
            (($offset += 1) <= $len)
              || return False;
            $len = $octets.subbuf($offset - 1).unpack('C');
            next if $len < 0x80;

            (($offset += 3) <= $len)
              || return False;
            $len = $octets.subbuf($offset - 4, 4).unpack('N') +& 0x7FFF_FFFF;
        }
        (($offset += $klen + $vlen) <= $olen)
          || return False;
    }
    True
}

## Full version of build_begin_request.
proto sub build_begin_request(|) is export {*}
multi sub build_begin_request(
  Int $request-id, %params, 
  Int :$role=FCGI_RESPONDER,
  Int :$flags=0,
  Buf :$stdin,
  Buf :$data
) {
    my $r = build_begin_request_record($request-id, $role, $flags)
          ~ build_stream(FCGI_PARAMS, $request-id, build_params(%params), :end);

    $r ~= build_stream(FCGI_STDIN, $request-id, $stdin, :end) if $stdin;
    $r ~= build_stream(FCGI_DATA,  $request-id, $data,  :end) if $data;
  
    $r;
}

## A short version, assumes defaults, provides a Buf STDIN stream.
multi sub build_begin_request(
  Int $request-id, %params, Buf $stdin
) {
    build_begin_request($request-id, %params, :$stdin)
}

## A short version, assumes defaults, provides a Str STDIN stream.
multi sub build_begin_request(
  Int $request-id, %params, Str $string
) {
    my $stdin = $string.encode;
    build_begin_request($request-id, %params, :$stdin)
}

## Full version of build_end_request.
proto sub build_end_request(|) is export {*}
multi sub build_end_request (
  Int $request-id, 
  Int :$app-status=0, 
  Int :$protocol-status=FCGI_REQUEST_COMPLETE,
  Buf :$stdout,
  Buf :$stderr
) {
    my $r = Buf.new;
    $r ~= build_stream(FCGI_STDOUT, $request-id, $stdout, :end) if $stdout;
    $r ~= build_stream(FCGI_STDERR, $request-id, $stderr, :end) if $stderr;
    $r ~= build_end_request_record($request-id, $app-status, $protocol-status)
}

## Short version of build_end_request, provides Buf STDOUT and STDERR streams.
multi sub build_end_request(
  Int $request-id, Buf $stdout, Buf $stderr?
) {
    build_end_request($request-id, :$stdout, :$stderr)
}

## Short version of build_end_request, provides Str STDOUT and STDERR streams.
multi sub build_end_request(
  Int $request-id, Str $strout, Str $strerr?
) {
    my $stdout = $strout.encode;
    my $stderr = $strerr.encode;
    build_end_request($request-id, :$stdout, :$stderr);
}

sub get_record_length(Buf $octets) is export {
    $octets.bytes >= FCGI_HEADER_LEN || return 0;
    my ($content-length, $padding-length) = $octets.unpack(FCGI_GetRecordLength);
    FCGI_HEADER_LEN + $content-length + $padding-length
}

sub is_known_type(Int $type) is export {
    $type > 0 && $type <= FCGI_MAXTYPE
}

sub is_discrete_type(Int $type) is export {
    $type == FCGI_BEGIN_REQUEST
           | FCGI_ABORT_REQUEST
           | FCGI_END_REQUEST
           | FCGI_GET_VALUES
           | FCGI_GET_VALUES_RESULT
           | FCGI_UNKNOWN_TYPE 
}

sub is_management_type(Int $type) is export {
    $type == FCGI_GET_VALUES | FCGI_GET_VALUES_RESULT | FCGI_UNKNOWN_TYPE
}

sub is_stream_type(Int $type) is export {
    $type == FCGI_PARAMS | FCGI_STDIN | FCGI_STDOUT | FCGI_STDERR | FCGI_DATA
}

sub get_type_name(Int $type) is export {
    FCGI_TypeNames[$type] || sprintf('0x%.2X', $type)
}

sub get_role_name(Int $role) {
    FCGI_RoleNames[$role] || sprintf('0x%.4X', $role)
}

sub get_protocol_status_name(Int $status) {
    FCGI_ProtocolStatusNames[$status] || sprintf('0x%.2X', $status)
}

# vim: expandtab shiftwidth=4
